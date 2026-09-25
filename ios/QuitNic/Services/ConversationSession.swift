import AVFoundation
import Foundation
import Observation
import Speech

/// A hands-free spoken turn with the coach.
///
/// The design follows the streaming-transcription model described by Meta's Muse voice
/// transcribe work: the microphone stays open, text is emitted continuously while a person
/// is still talking, and the decision to hand the turn over is made from the words that
/// have arrived so far rather than from a button. Nobody holds anything down, and nobody
/// says "over".
///
/// Three properties carry that idea here:
///
/// - **Streaming.** Partial transcripts land while you speak, so `liveTranscript` is
///   readable during the sentence, not after it.
/// - **Adaptive endpointing.** The pause that ends a turn is not a fixed timeout. A
///   sentence that trails off on "and" or "because" is given far longer than one that has
///   already landed on a question mark, which is what stops the coach cutting people off
///   mid-thought.
/// - **Barge-in.** Recognition keeps running while the coach speaks. Two words from the
///   person are enough to stop the reply and give the turn straight back.
@MainActor
@Observable
final class ConversationSession {
    enum Phase: Equatable {
        case idle, listening, thinking, speaking

        var label: String {
            switch self {
            case .idle: "Tap to start"
            case .listening: "Listening"
            case .thinking: "Thinking"
            case .speaking: "Coach is talking"
            }
        }
    }

    struct Reply: Sendable {
        let text: String
        let isSafetyResponse: Bool
        /// A failed turn is still spoken, but it must not end the session.
        let isFailure: Bool

        init(text: String, isSafetyResponse: Bool = false, isFailure: Bool = false) {
            self.text = text
            self.isSafetyResponse = isSafetyResponse
            self.isFailure = isFailure
        }
    }

    private(set) var phase: Phase = .idle
    /// What the person is saying right now, updated mid-sentence.
    private(set) var liveTranscript = ""
    /// What the coach last said, kept on screen so a spoken reply is also readable.
    private(set) var lastReply = ""
    /// Smoothed input loudness, 0...1, for the listening orb.
    private(set) var level: Double = 0
    private(set) var isMuted = false
    var errorMessage: String?

    /// Past this a turn is no longer a turn, and the recognizer's own session limit is
    /// close behind. The turn is closed with whatever has been said.
    private static let maximumTurnSeconds: Double = 45
    /// Two words, so a stray click or the tail of the coach's own voice cannot barge in.
    private static let minimumBargeInWords = 2

    /// Supplied by the screen once it has a data context. Set before `start`.
    var respond: (String) async -> Reply = { _ in
        Reply(text: "Coach is not connected yet.", isFailure: true)
    }
    private let narrator = SpeechNarrator()
    private var audioEngine: AVAudioEngine?
    private var hasInstalledTap = false
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var sink: AudioSink?
    private var endpointTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var turnStartedAt: Date?
    private var generation = 0

    var isRunning: Bool { phase != .idle }

    // MARK: - Lifecycle

    func start(opening: String?) async {
        guard phase == .idle else { return }
        generation += 1
        let generation = self.generation
        errorMessage = nil
        liveTranscript = ""
        guard await microphoneGranted() else {
            errorMessage = "Conversation needs the microphone. Enable it in Settings, or use the chat instead."
            return
        }
        guard await speechGranted() else {
            errorMessage = "Conversation needs speech recognition. Enable it in Settings, or use the chat instead."
            return
        }
        guard generation == self.generation else { return }
        do {
            try startAudio()
        } catch {
            stopAudio()
            errorMessage = "Voice could not start. Try again, or use the chat instead."
            return
        }
        startLevelPump()
        if let opening, !opening.isEmpty {
            speak(Reply(text: opening))
        } else {
            beginListening()
        }
    }

    func stop() {
        generation += 1
        endpointTask?.cancel(); endpointTask = nil
        levelTask?.cancel(); levelTask = nil
        narrator.stop()
        stopRecognition()
        stopAudio()
        phase = .idle
        liveTranscript = ""
        level = 0
    }

    func toggleMute() {
        isMuted.toggle()
        sink?.setMuted(isMuted)
        if isMuted {
            endpointTask?.cancel()
            endpointTask = nil
        } else if phase == .listening {
            scheduleEndpoint()
        }
    }

    /// Ends the current turn immediately, for somebody who would rather not wait out the
    /// pause. Nothing about the session changes otherwise.
    func handOverTurn() {
        guard phase == .listening else { return }
        finalizeTurn()
    }

    // MARK: - Audio graph

    private func startAudio() throws {
        let session = AVAudioSession.sharedInstance()
        // .voiceChat gives the input the system's echo canceller, which is what makes it
        // safe to keep recognizing while the coach's reply is playing out of the speaker.
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        audioEngine = engine
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        let sink = AudioSink()
        self.sink = sink
        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, _ in
            sink.append(buffer)
        }
        hasInstalledTap = true
        engine.prepare()
        try engine.start()
    }

    private func stopAudio() {
        if let audioEngine {
            if audioEngine.isRunning { audioEngine.stop() }
            if hasInstalledTap { audioEngine.inputNode.removeTap(onBus: 0) }
        }
        hasInstalledTap = false
        audioEngine = nil
        sink = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// The tap runs on a realtime thread and cannot read observable state, so loudness is
    /// polled off the sink instead of pushed out of the callback.
    private func startLevelPump() {
        levelTask?.cancel()
        levelTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let target = self.sink?.currentLevel ?? 0
                self.level += (target - self.level) * 0.35
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    // MARK: - Recognition

    private func beginListening() {
        phase = .listening
        liveTranscript = ""
        turnStartedAt = .now
        startRecognition()
    }

    private func startRecognition() {
        stopRecognition()
        let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition is not available in this language yet."
            return
        }
        self.recognizer = recognizer
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep the audio on the phone whenever the device can do it. Only the resulting
        // text ever reaches the coach.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request
        sink?.attach(request)
        let generation = self.generation
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let failed = error != nil
            Task { @MainActor [weak self] in
                guard let self, generation == self.generation else { return }
                if let text, !text.isEmpty { self.heard(text) }
                if failed, self.phase == .listening, self.liveTranscript.isEmpty {
                    // A recognizer that gives up between turns is restartable; only say so
                    // if it happens while nothing is in flight.
                    self.startRecognition()
                }
            }
        }
    }

    private func stopRecognition() {
        sink?.attach(nil)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
    }

    private func heard(_ text: String) {
        switch phase {
        case .speaking:
            guard text.split(separator: " ").count >= Self.minimumBargeInWords else { return }
            narrator.stop()
            phase = .listening
            turnStartedAt = .now
            liveTranscript = text
            scheduleEndpoint()
        case .listening:
            liveTranscript = text
            if let turnStartedAt, Date().timeIntervalSince(turnStartedAt) > Self.maximumTurnSeconds {
                finalizeTurn()
            } else {
                scheduleEndpoint()
            }
        case .thinking, .idle:
            break
        }
    }

    // MARK: - Adaptive endpointing

    /// Words that almost always have more sentence behind them. Somebody pausing after
    /// "because" is thinking, not finished, so the session waits noticeably longer.
    private static let continuationWords: Set<String> = [
        "and", "but", "or", "so", "because", "cause", "if", "when", "while", "that",
        "then", "than", "with", "for", "to", "of", "at", "in", "on", "my", "the", "a",
        "an", "i", "im", "its", "it", "was", "is", "like", "just", "um", "uh", "erm",
        "well", "maybe", "kinda", "sorta", "really", "about",
    ]

    private func scheduleEndpoint() {
        endpointTask?.cancel()
        guard !isMuted else { return }
        let window = silenceWindow(for: liveTranscript)
        endpointTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(window))
            guard let self, !Task.isCancelled, self.phase == .listening else { return }
            self.finalizeTurn()
        }
    }

    /// How long a pause has to run before the turn is handed over, in milliseconds.
    ///
    /// A fixed timeout is wrong in both directions: short enough to feel responsive after
    /// a finished question, it chops people off mid-thought; long enough to be safe there,
    /// every exchange drags. The window is chosen from how finished the words sound.
    func silenceWindow(for transcript: String) -> Int {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 1_500 }
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "\n" })
        let last = words.last.map {
            String($0).lowercased().filter { $0.isLetter || $0.isNumber }
        } ?? ""
        if Self.continuationWords.contains(last) { return 1_700 }
        if trimmed.hasSuffix("?") { return 550 }
        if trimmed.hasSuffix(".") || trimmed.hasSuffix("!") { return 700 }
        // Very short openers ("I'm struggling") are usually the start of something.
        if words.count <= 2 { return 1_400 }
        return 1_050
    }

    // MARK: - Turns

    private func finalizeTurn() {
        endpointTask?.cancel(); endpointTask = nil
        let spoken = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard spoken.count >= 2 else {
            // Silence, or a cough. Stay listening rather than sending the coach nothing.
            liveTranscript = ""
            return
        }
        phase = .thinking
        stopRecognition()
        liveTranscript = spoken
        let generation = self.generation
        Task { @MainActor [weak self] in
            guard let self else { return }
            let reply = await self.respond(spoken)
            guard generation == self.generation, self.phase == .thinking else { return }
            self.liveTranscript = ""
            self.speak(reply)
        }
    }

    private func speak(_ reply: Reply) {
        lastReply = reply.text
        phase = .speaking
        // Listening resumes before the reply starts playing, so an interruption in the
        // first half-second is heard like any other.
        startRecognition()
        let generation = self.generation
        narrator.speak(reply.text) { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, generation == self.generation, self.phase == .speaking else { return }
                self.beginListening()
            }
        }
    }

    // MARK: - Permissions

    private func microphoneGranted() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
    }

    private func speechGranted() async -> Bool {
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

/// The only object the realtime audio tap is allowed to touch.
///
/// The tap closure runs on an audio thread, so it must not reach into `@MainActor` state.
/// It hands buffers here; the session pulls loudness back out on its own schedule.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var level: Double = 0
    private var muted = false

    var currentLevel: Double { lock.withLock { level } }

    func attach(_ request: SFSpeechAudioBufferRecognitionRequest?) {
        lock.withLock { self.request = request }
    }

    func setMuted(_ muted: Bool) {
        lock.withLock {
            self.muted = muted
            if muted { level = 0 }
        }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        let loudness = Self.loudness(of: buffer)
        lock.withLock {
            guard !muted else { return }
            level = loudness
            request?.append(buffer)
        }
    }

    /// Root-mean-square of the first channel, mapped onto a 0...1 curve that keeps normal
    /// speech in the visible middle of the range instead of pinned near zero.
    private static func loudness(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        let rms = Double((sum / Float(count)).squareRoot())
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 50) / 45))
    }
}

/// Speaks the coach's reply and reports when it has finished.
@MainActor
private final class SpeechNarrator: NSObject, @preconcurrency AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (() -> Void)?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String, completion: @escaping () -> Void) {
        self.completion = completion
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.preferredVoice()
        // A shade under the default. A craving is not the moment to be talked at quickly.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.94
        utterance.pitchMultiplier = 1.0
        utterance.postUtteranceDelay = 0.1
        synthesizer.speak(utterance)
    }

    func stop() {
        completion = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    }

    /// Prefer an enhanced or premium voice when the person has one downloaded; the compact
    /// default reads as robotic in a conversation this personal.
    private static func preferredVoice() -> AVSpeechSynthesisVoice? {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        return candidates.first(where: { $0.quality == .premium })
            ?? candidates.first(where: { $0.quality == .enhanced })
            ?? AVSpeechSynthesisVoice(language: language)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let completion = self.completion
        self.completion = nil
        completion?()
    }
}
