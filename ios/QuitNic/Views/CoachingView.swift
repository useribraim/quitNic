import AVFoundation
import Foundation
import Observation
import Speech
import SwiftData
import SwiftUI

struct CoachingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @Query private var plans: [QuitPlan]
    @State private var model = CoachingViewModel()
    @State private var speech = PushToTalkController()
    private let prompts = ["I’m having a craving", "Help me plan the next hour", "I feel like I might slip"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if messages.isEmpty && !model.isLoading { welcome }
                            ForEach(messages) { message in ChatBubble(message: message).id(message.id) }
                            if model.isLoading { HStack { SwiftUI.ProgressView(); Text("Thinking through this with you…").font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk) }.padding(.horizontal, 6) }
                        }.padding(.horizontal, 20).padding(.vertical, 18)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } } }
                }
                if let error = model.errorMessage { errorBanner(error) }
                composer
            }
            .background(QuitNicTheme.warmBackground.ignoresSafeArea())
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) { Image(systemName: "message.and.waveform.fill").font(.title2).foregroundStyle(QuitNicTheme.teal); VStack(alignment: .leading, spacing: 3) { Text("A calmer next step").font(.title3.weight(.bold)); Text("Use Coach for reflection and planning after Rescue.").font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk) } }
            Text("I can help you make the next few minutes easier. I’m not a medical service, but I can stay with you while you choose a practical coping step.").font(.subheadline).foregroundStyle(QuitNicTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) { Text("Try a prompt").font(.caption.weight(.bold)).foregroundStyle(QuitNicTheme.secondaryInk); ForEach(prompts, id: \.self) { prompt in Button { model.draft = prompt } label: { HStack { Text(prompt); Spacer(); Image(systemName: "arrow.up.right") } }.buttonStyle(PromptButtonStyle()) } }
        }.padding(18).background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 24)).overlay(RoundedRectangle(cornerRadius: 24).stroke(QuitNicTheme.teal.opacity(0.12)))
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let error = speech.errorMessage {
                Label(error, systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            } else if speech.isRecording {
                Label("Listening… release when you are done", systemImage: "waveform")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(QuitNicTheme.teal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
            }
            HStack(alignment: .bottom, spacing: 10) {
                PushToTalkButton(isRecording: speech.isRecording, mode: transcriptionMode) {
                    Task { await startVoiceInput() }
                } onRelease: {
                    Task { await finishVoiceInput() }
                }
            TextField("What’s happening?", text: $model.draft, axis: .vertical).lineLimit(1...4).padding(.horizontal, 14).padding(.vertical, 11).background(.white, in: RoundedRectangle(cornerRadius: 18)).accessibilityIdentifier("coachInput")
            Button { Task { await send() } } label: { Image(systemName: "arrow.up").font(.headline.weight(.bold)).frame(width: 42, height: 42).foregroundStyle(.white).background(QuitNicTheme.actionTeal, in: Circle()) }.accessibilityLabel("Send").disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading).opacity(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isLoading ? 0.45 : 1)
            }
            .padding(.horizontal, 16)
        }
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func errorBanner(_ error: String) -> some View { HStack(alignment: .top, spacing: 10) { Image(systemName: model.requiresReconnect ? "key.fill" : "wifi.exclamationmark").foregroundStyle(.orange); VStack(alignment: .leading, spacing: 3) { Text(model.requiresReconnect ? "Reconnect Coach" : "Coach is unavailable").font(.subheadline.weight(.semibold)); Text(error).font(.caption).foregroundStyle(QuitNicTheme.secondaryInk) }; Spacer(); Button(model.requiresReconnect ? "Reconnect" : "Retry") { Task { if model.requiresReconnect { await reconnect() } else { await retry() } } }.font(.subheadline.weight(.semibold)).disabled(model.isLoading) }.padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).padding(.horizontal, 16).padding(.bottom, 8) }
    private func persist(_ message: ChatMessage) { context.insert(message); try? context.save() }
    private func send() async { await model.send(messages: messages, save: persist) }
    private func retry() async { await model.retry(messages: messages, save: persist) }
    private func reconnect() async {
        guard let plan = plans.first else { return }
        await model.reconnectAndRetry(messages: messages, plan: plan, context: context, save: persist)
    }

    private var transcriptionMode: TranscriptionMode {
        TranscriptionMode(rawValue: UserDefaults.standard.string(forKey: "transcriptionMode") ?? "") ?? .onDevice
    }

    private func startVoiceInput() async {
        await speech.start(mode: transcriptionMode)
    }

    private func finishVoiceInput() async {
        guard let audioURL = speech.stop() else { return }
        defer { try? FileManager.default.removeItem(at: audioURL) }
        if transcriptionMode == .enhancedCloud {
            do { model.draft = try await APIClient.shared.transcribe(audioURL: audioURL).text }
            catch { speech.errorMessage = "Enhanced transcription is unavailable. Try on-device speech or type instead." }
        } else {
            model.draft = speech.transcript
        }
    }
}

private struct PushToTalkButton: View {
    let isRecording: Bool
    let mode: TranscriptionMode
    let onPress: () -> Void
    let onRelease: () -> Void

    var body: some View {
        Image(systemName: isRecording ? "mic.fill" : "mic")
            .font(.headline.weight(.bold))
            .foregroundStyle(isRecording ? .white : QuitNicTheme.teal)
            .frame(width: 42, height: 42)
            .background(isRecording ? .red : QuitNicTheme.teal.opacity(0.12), in: Circle())
            .scaleEffect(isRecording ? 1.08 : 1)
            .animation(.easeInOut(duration: 0.16), value: isRecording)
            .accessibilityLabel(isRecording ? "Recording voice input" : "Push to talk")
            .accessibilityHint(mode == .onDevice ? "Hold to dictate on this device" : "Hold to send a short clip for enhanced cloud transcription")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !isRecording { onPress() } }
                    .onEnded { _ in onRelease() }
            )
    }
}

@MainActor
@Observable
private final class PushToTalkController {
    var isRecording = false
    var transcript = ""
    var errorMessage: String?

    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?

    func start(mode: TranscriptionMode) async {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""
        guard await microphonePermissionGranted() else {
            errorMessage = "Microphone access is needed for Push to Talk."
            return
        }
        if mode == .onDevice, !(await speechPermissionGranted()) {
            errorMessage = "Speech recognition access is needed for on-device transcription."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            let url = FileManager.default.temporaryDirectory.appending(path: "quitnic-\(UUID().uuidString).m4a")
            recordingURL = url
            audioFile = try AVAudioFile(forWriting: url, settings: format.settings, commonFormat: .pcmFormatFloat32, interleaved: false)

            if mode == .onDevice {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                recognitionRequest = request
                recognitionTask = SFSpeechRecognizer(locale: .current)?.recognitionTask(with: request) { [weak self] result, error in
                    guard let self else { return }
                    if let result { self.transcript = result.bestTranscription.formattedString }
                    if error != nil && self.isRecording { self.errorMessage = "On-device transcription could not finish." }
                }
            }

            input.installTap(onBus: 0, bufferSize: 1_024, format: format) { [weak self] buffer, _ in
                try? self?.audioFile?.write(from: buffer)
                self?.recognitionRequest?.append(buffer)
            }
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
        stopEngine()
        return recordingURL
    }

    private func stopEngine() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.finish()
        recognitionRequest = nil
        recognitionTask = nil
        audioFile = nil
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

private struct PromptButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label.font(.subheadline.weight(.medium)).foregroundStyle(QuitNicTheme.ink).padding(.horizontal, 13).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading).background(QuitNicTheme.warmBackground, in: RoundedRectangle(cornerRadius: 14)).opacity(configuration.isPressed ? 0.65 : 1) }
}

private struct ChatBubble: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 7) {
            HStack { if message.role == "user" { Spacer() }; Text(message.content).font(.body).foregroundStyle(message.isSafetyResponse ? Color(red: 0.45, green: 0.06, blue: 0.08) : QuitNicTheme.ink).padding(.horizontal, 15).padding(.vertical, 12).background(message.isSafetyResponse ? Color.red.opacity(0.12) : message.role == "user" ? QuitNicTheme.teal.opacity(0.16) : .white, in: RoundedRectangle(cornerRadius: 18)); if message.role != "user" { Spacer() } }
            if message.isSafetyResponse { Link(destination: URL(string: "https://findahelpline.com")!) { Label("Find local crisis support", systemImage: "arrow.up.right.square").font(.caption.weight(.semibold)).foregroundStyle(.red) }.accessibilityHint("Opens a directory of crisis support services") }
        }.frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading).accessibilityElement(children: .combine).accessibilityLabel("\(message.role == "user" ? "You" : "Coach"): \(message.content)")
    }
}
