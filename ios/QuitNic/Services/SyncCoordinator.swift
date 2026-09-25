import Foundation
import SwiftData

/// Everything the app does that crosses the network, in one place.
///
/// The views used to call `APIClient` and the keychain directly — onboarding, settings,
/// the plan editor and the coaching view model each had their own slightly different
/// idea of what "save the plan" or "handle a 401" meant. A screen now states intent and
/// this decides how it reaches the server, including when the answer is "later".
@MainActor
enum SyncCoordinator {
    /// Persist a plan change server-side, falling back to the outbox. Never throws: a
    /// plan edit is already saved locally by the time it gets here, and the person should
    /// not be blocked on connectivity.
    /// - Returns: `true` if it reached the server now, `false` if it was queued.
    @discardableResult
    static func savePlan(
        _ plan: QuitPlan,
        context: ModelContext,
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async -> Bool {
        guard auth.existingToken() != nil else {
            // A local-only plan has nothing to reach yet, but the edit still has to sync
            // once a connection exists — otherwise it is silently dropped.
            try? await OutboxService.enqueue(plan: plan, context: context)
            return false
        }
        do {
            try await client.save(plan: QuitPlanRequest(plan))
            return true
        } catch APIError.unauthorized {
            if (try? await auth.recoverFromUnauthorized()) != nil,
               (try? await client.save(plan: QuitPlanRequest(plan))) != nil {
                return true
            }
            try? await OutboxService.enqueue(plan: plan, context: context)
            return false
        } catch {
            try? await OutboxService.enqueue(plan: plan, context: context)
            return false
        }
    }

    /// Onboarding's hand-off: register if needed, then sync the new plan. Failure is not
    /// an error the person has to act on — the plan is already usable offline — but it
    /// must leave queued work behind rather than evaporating.
    static func registerAndSyncNewPlan(
        _ plan: QuitPlan,
        context: ModelContext,
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async {
        guard (try? await auth.token()) != nil else {
            try? await OutboxService.enqueue(plan: plan, context: context)
            return
        }
        await savePlan(plan, context: context, client: client, auth: auth)
    }

    /// Called on every foreground. Picks up anything left behind, including check-ins
    /// whose original send failed before an operation was ever recorded.
    static func flush(
        context: ModelContext,
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async {
        guard !ProcessInfo.processInfo.arguments.contains("-ui-testing-offline") else {
            await OutboxService.enqueueUnsyncedCheckIns(context: context)
            return
        }
        await retryPendingDeletions(client: client, auth: auth)
        await OutboxService.enqueueUnsyncedCheckIns(context: context)
        await OutboxService.flush(context: context, client: client, auth: auth)
    }

    /// Re-establish a session and push everything pending. Used by Coach's reconnect.
    static func reconnect(
        plan: QuitPlan,
        context: ModelContext,
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async throws {
        _ = try await auth.recoverFromUnauthorized()
        await savePlan(plan, context: context, client: client, auth: auth)
        await flush(context: context, client: client, auth: auth)
    }

    static func deleteAccount(
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async throws {
        if auth.existingToken() != nil {
            try await client.deleteAccount()
        }
        await auth.signOut()
    }

    static func deleteCoachingHistory(
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async throws {
        // A local-only plan never registered, so there is nothing server-side to delete.
        guard auth.existingToken() != nil else { return }
        try await client.deleteCoachingHistory()
    }

    /// Deletion requests survive an offline local wipe. The anonymous token is retained
    /// solely until the service confirms deletion, then removed immediately.
    static func retryPendingDeletions(
        client: APIClient = .shared,
        auth: AuthService = .shared
    ) async {
        if UserDefaults.standard.bool(forKey: "pendingCoachingDeletion"), auth.existingToken() != nil {
            if (try? await client.deleteCoachingHistory()) != nil {
                UserDefaults.standard.removeObject(forKey: "pendingCoachingDeletion")
            }
        }
        if UserDefaults.standard.bool(forKey: "pendingAccountDeletion") {
            guard auth.existingToken() != nil else {
                UserDefaults.standard.removeObject(forKey: "pendingAccountDeletion")
                return
            }
            if (try? await client.deleteAccount()) != nil {
                UserDefaults.standard.removeObject(forKey: "pendingAccountDeletion")
                await auth.signOut()
            }
        }
    }
}
