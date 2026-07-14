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
            let registration = try await APIClient.shared.register()
            try KeychainStore.saveToken(registration.accessToken)
            try await APIClient.shared.save(plan: QuitPlanRequest(
                nicotineType: plan.nicotineType,
                dailyConsumption: plan.dailyConsumption,
                unitCost: plan.unitCost,
                quitDate: plan.quitDate,
                motivation: plan.motivation,
                reminderHour: plan.reminderHour
            ))
            try await restoreLocalCheckIns(context: context)
            requiresReconnect = false
            await requestResponse(for: lastFailedMessage, messages: Array(messages.dropLast()), save: save)
        } catch {
            requiresReconnect = true
            errorMessage = "Could not reconnect yet. Check your connection and try again."
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
            requiresReconnect = (error as? APIError) == .unauthorized
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "Coaching is unavailable."
        }
    }

    private func restoreLocalCheckIns(context: ModelContext) async throws {
        let checkIns = try context.fetch(FetchDescriptor<CravingCheckIn>(sortBy: [SortDescriptor(\.occurredAt)]))
        for checkIn in checkIns {
            let request = CheckInRequest(
                intensity: checkIn.intensity,
                trigger: checkIn.trigger,
                copingAction: checkIn.copingAction,
                note: checkIn.note,
                resisted: checkIn.resisted,
                occurredAt: checkIn.occurredAt
            )
            _ = try await APIClient.shared.post(checkIn: request, idempotencyKey: checkIn.id.uuidString)
            checkIn.synced = true
        }
        try context.save()
        await OutboxService.flush(context: context)
    }
}
