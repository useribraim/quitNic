import SwiftData
import SwiftUI

struct CoachingView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \ChatMessage.createdAt) private var messages: [ChatMessage]
    @State private var model = CoachingViewModel()
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView { LazyVStack(spacing: 10) { ForEach(messages) { message in ChatBubble(message: message).id(message.id) }; if model.isLoading { SwiftUI.ProgressView("Thinking…") } }.padding() }
                        .onChange(of: messages.count) { _, _ in if let id = messages.last?.id { proxy.scrollTo(id) } }
                }
                if let error = model.errorMessage { HStack { Text(error).font(.caption); Spacer(); Button("Retry") { Task { await retry() } } }.padding(8).background(.orange.opacity(0.18)) }
                HStack { TextField("What’s happening?", text: $model.draft, axis: .vertical).textFieldStyle(.roundedBorder).accessibilityIdentifier("coachInput"); Button("Send") { Task { await send() } }.disabled(model.draft.trimmingCharacters(in: .whitespaces).isEmpty || model.isLoading) }.padding()
            }.navigationTitle("Coach")
        }
    }
    private func persist(_ message: ChatMessage) { context.insert(message); try? context.save() }
    private func send() async { await model.send(messages: messages, save: persist) }
    private func retry() async { await model.retry(messages: messages, save: persist) }
}

private struct ChatBubble: View {
    let message: ChatMessage
    var body: some View { HStack { if message.role == "user" { Spacer() }; Text(message.content).padding(12).background(message.isSafetyResponse ? Color.red.opacity(0.15) : message.role == "user" ? Color.green.opacity(0.2) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)); if message.role != "user" { Spacer() } }.accessibilityLabel("\(message.role == "user" ? "You" : "Coach"): \(message.content)") }
}
