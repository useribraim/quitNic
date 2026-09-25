import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class CoachingViewModel {
    var draft = ""
    var isLoading = false
    var errorMessage: String?
    var requiresReconnect = false
    private(set) var lastFailedMessage: String?

    /// A local-first plan may never have registered, so "your session expired" would be
    /// untrue for a brand-new person. Distinguish first connection from reconnection.
    var hasEverConnected: Bool { AuthService.shared.existingToken() != nil }

    func send(messages: [ChatMessage], save: (ChatMessage) -> Void) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }
        draft = ""; errorMessage = nil; requiresReconnect = false; isLoading = true
        save(ChatMessage(role: "user", content: text))
        await requestResponse(for: text, messages: messages, save: save)
        isLoading = false
    }

    func retry(messages: [ChatMessage], save: (ChatMessage) -> Void) async {
        guard let lastFailedMessage, !isLoading else { return }
        errorMessage = nil; isLoading = true
        await requestResponse(for: lastFailedMessage, messages: Array(messages.dropLast()), save: save)
        isLoading = false
    }

    func reconnectAndRetry(
        messages: [ChatMessage],
        plan: QuitPlan,
        context: ModelContext,
        save: (ChatMessage) -> Void
    ) async {
        guard let lastFailedMessage, !isLoading else { return }
        errorMessage = nil; isLoading = true
        do {
            try await SyncCoordinator.reconnect(plan: plan, context: context)
            requiresReconnect = false
            await requestResponse(for: lastFailedMessage, messages: Array(messages.dropLast()), save: save)
        } catch {
            requiresReconnect = (error as? APIError) == .unauthorized
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Your session was restored, but QuitNic could not sync yet. Please try again."
        }
        isLoading = false
    }

    private func requestResponse(for text: String, messages: [ChatMessage], save: (ChatMessage) -> Void) async {
        let conversation = messages.suffix(10).map { ConversationTurn(role: $0.role, content: $0.content) }
        do {
            let response = try await APIClient.shared.coach(CoachingRequest(message: text, recentContext: conversation))
            save(ChatMessage(role: "assistant", content: response.message, isSafetyResponse: response.isSafetyResponse))
            lastFailedMessage = nil
        } catch {
            lastFailedMessage = text
            let needsSession = (error as? APIError) == .unauthorized
            requiresReconnect = needsSession
            if needsSession && !hasEverConnected {
                errorMessage = "Coach needs a one-time private connection before it can reply. Your plan and history stay on this device."
            } else {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? "Coaching is unavailable."
            }
        }
    }
}
