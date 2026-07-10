# Verification matrix

Automated backend tests cover health, authentication boundaries, quit-plan synchronization, progress math, idempotent check-ins, safety responses, provider responses, and deletion. iOS tests cover progress/date boundaries, response-cache expiry, snake_case networking, and fresh-install onboarding.

Before each external build, manually verify on at least one physical device:

1. Clean install, anonymous registration, onboarding, relaunch persistence, dark mode, Dynamic Type, and VoiceOver labels.
2. Check-in online, check-in in airplane mode, relaunch while offline, then reconnect and confirm exactly-once synchronization.
3. Normal coaching, backend timeout, malformed response, rate limit, expired token, and fixed urgent-language response.
4. Notification allowed and denied states, daily delivery, foreground/background transitions, and timezone change.
5. Server-confirmed account deletion, Keychain removal, notification removal, and return to onboarding.
6. Upgrade from the previous TestFlight build without losing the quit plan or check-in history.

