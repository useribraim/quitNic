import Foundation
import Observation

@MainActor
@Observable
final class CoachingViewModel {
    var draft = ""
    var isLoading = false
    var errorMessage: String?
    private(set) var lastFailedMessage: String?

    func send(messages: [ChatMessage], save: (ChatMessage) -> Void) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        draft = ""; errorMessage = nil; isLoading = true
        save(ChatMessage(role: "user", content: text))
        let context = messages.suffix(10).map { ConversationTurn(role: $0.role, content: $0.content) }
        do {
            let response = try await APIClient.shared.coach(CoachingRequest(message: text, recentContext: context))
            save(ChatMessage(role: "assistant", content: response.message, isSafetyResponse: response.isSafetyResponse))
            lastFailedMessage = nil
        } catch {
            lastFailedMessage = text
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Coaching is unavailable."
        }
        isLoading = false
    }

    func retry(messages: [ChatMessage], save: (ChatMessage) -> Void) async {
        guard let lastFailedMessage else { return }; draft = lastFailedMessage
        await send(messages: messages, save: save)
    }
}
