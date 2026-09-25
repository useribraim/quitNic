import AVFoundation
import Foundation
import Observation
import Speech
import SwiftUI

struct PushToTalkButton: View {
    let isRecording: Bool
    let mode: TranscriptionMode
    let onPress: () -> Void
    let onRelease: () -> Void
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(HorizonTheme.accent.opacity(0.16))
                .frame(width: 42, height: 42)
                .scaleEffect(isRecording && isPulsing ? 1.32 : 1)
                .opacity(isRecording ? (isPulsing ? 0 : 0.45) : 0)
            Image(systemName: isRecording ? "mic.fill" : "mic")
                .font(.headline.weight(.bold))
                .foregroundStyle(isRecording ? .white : HorizonTheme.accent)
                .frame(width: 42, height: 42)
                .background(isRecording ? HorizonTheme.accent : HorizonTheme.surface, in: Circle())
                .scaleEffect(isRecording ? 1.05 : 1)
        }
            .animation(.easeInOut(duration: 0.16), value: isRecording)
            .onChange(of: isRecording, initial: true) { _, recording in
                if recording {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { isPulsing = true }
                } else {
                    isPulsing = false
                }
            }
            .accessibilityLabel(isRecording ? "Recording voice input" : "Push to talk")
            .accessibilityHint(mode == .onDevice ? "Hold to dictate on this device" : "Hold to send a short clip for enhanced cloud transcription")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                if isRecording { onRelease() } else { onPress() }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isRecording { onPress() } }
                    .onEnded { _ in onRelease() }
            )
    }
}

/// Everything the audio tap touches, on its own lock.
///
/// The tap closure runs on a realtime audio thread, so it must not reach into a
/// `@MainActor` object's stored properties — that was an actual data race, and one Swift
/// 6's concurrency checking rejects outright. This sink is the only thing it talks to.
private final class RecordingSink: @unchecked Sendable {
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var framesWritten: AVAudioFramePosition = 0
    private let frameLimit: AVAudioFramePosition
    private var hitLimit = false

    init(file: AVAudioFile, request: SFSpeechAudioBufferRecognitionRequest?, frameLimit: AVAudioFramePosition) {
        self.file = file
        self.request = request
        self.frameLimit = frameLimit
    }

    var reachedLimit: Bool { lock.withLock { hitLimit } }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock {
            guard let file else { return }
            guard framesWritten < frameLimit else {
                hitLimit = true
                return
            }
            try? file.write(from: buffer)
            framesWritten += AVAudioFramePosition(buffer.frameLength)
            request?.append(buffer)
        }
    }

    /// Releases the file so its header is finalised before anyone reads it.
    func finish() {
        lock.withLock {
            file = nil
            request = nil
        }
    }
}

@MainActor
@Observable
final class PushToTalkController {
    var isRecording = false
    var transcript = ""
    var errorMessage: String?

    /// A held button is not a dictation session. Past a minute the upload gets large and
    /// the transcript stops being a message, so the recording simply stops growing.
    static let maximumRecordingSeconds: Double = 60

    // AVAudioEngine builds and retains an audio graph. Allocate it only when recording
    // actually starts, then release it on stop so merely opening Coach stays cheap.
    private var audioEngine: AVAudioEngine?
    private var hasInstalledInputTap = false
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var sink: RecordingSink?
    private var recordingURL: URL?
    private var startGeneration = 0

    func start(mode: TranscriptionMode) async {
        guard !isRecording else { return }
        startGeneration += 1
        let generation = startGeneration
        errorMessage = nil
        transcript = ""
        guard await microphonePermissionGranted(), generation == startGeneration, !Task.isCancelled else {
            if generation == startGeneration, !Task.isCancelled { errorMessage = "Microphone access is needed for Push to Talk." }
            return
        }
        if mode == .onDevice {
            guard await speechPermissionGranted(), generation == startGeneration, !Task.isCancelled else {
                if generation == startGeneration, !Task.isCancelled { errorMessage = "Speech recognition access is needed for on-device transcription." }
                return
            }
        }
        guard generation == startGeneration, !Task.isCancelled else {
            return
        }
        do {
            let audioEngine = AVAudioEngine()
            self.audioEngine = audioEngine
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            let url = FileManager.default.temporaryDirectory.appending(path: "quitnic-\(UUID().uuidString).m4a")
            recordingURL = url

            // Actually AAC in an MPEG-4 container, which is what the `.m4a` extension and
            // the upload's `audio/mp4` content type claim. This used to hand AVAudioFile
            // the input node's own settings, writing uncompressed float32 PCM into a file
            // named `.m4a` — roughly 100x larger, and unreadable by any m4a decoder.
            let fileSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]
            let file = try AVAudioFile(
                forWriting: url,
                settings: fileSettings,
                commonFormat: .pcmFormatFloat32,
                interleaved: false
            )

            if mode == .onDevice {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                recognitionRequest = request
                recognitionTask = SFSpeechRecognizer(locale: .current)?.recognitionTask(with: request) { [weak self] result, error in
                    // Delivered on an arbitrary queue; hop before touching observable state.
                    let text = result?.bestTranscription.formattedString
                    let failed = error != nil
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if let text { self.transcript = text }
                        if failed && self.isRecording { self.errorMessage = "On-device transcription could not finish." }
                    }
                }
            }

            let sink = RecordingSink(
                file: file,
                request: recognitionRequest,
                frameLimit: AVAudioFramePosition(format.sampleRate * Self.maximumRecordingSeconds)
            )
            self.sink = sink
            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
                sink.append(buffer)
            }
            hasInstalledInputTap = true
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            stopEngine()
            errorMessage = "Voice input could not start. Try again or type instead."
        }
    }

    func stop() -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        let reachedLimit = sink?.reachedLimit ?? false
        stopEngine()
        if reachedLimit {
            errorMessage = "Only the first minute was recorded. Send it, or hold again for a shorter message."
        }
        return recordingURL
    }

    /// Invalidates permission requests that may still be suspended in `start` and stops
    /// any live graph. A permission callback must never begin recording after Coach left.
    func cancel() -> URL? {
        startGeneration += 1
        return stop()
    }

    private func stopEngine() {
        if let audioEngine {
            if audioEngine.isRunning { audioEngine.stop() }
            if hasInstalledInputTap { audioEngine.inputNode.removeTap(onBus: 0) }
        }
        hasInstalledInputTap = false
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        // Close the file before the caller uploads it, so the container is finalised.
        sink?.finish()
        sink = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func microphonePermissionGranted() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private func speechPermissionGranted() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0 == .authorized) }
            }
        default: return false
        }
    }
}
