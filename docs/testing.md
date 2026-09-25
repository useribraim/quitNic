# Verification matrix

Automated backend tests cover health, authentication boundaries, quit-plan synchronization, progress math, idempotent check-ins, safety responses, provider responses, rate limits, transcription boundaries, and deletion. iOS unit tests cover nicotine-type-specific milestones, progress/date boundaries, navigation URL parsing, snake-case networking, session recovery, milestone acknowledgement, zoom/light math, and retry-safe offline outbox replacement/deletion.

Focused Simulator UI tests cover the canonical Today/Journey navigation, Rescue-before-form behaviour, accidental-flow exits, Quick Log save and durable draft restoration, slips, offline relaunch, ordinary-log Undo, history correction/deletion, Coach, accessibility audits, keyboard reachability at accessibility XXXL, landscape Today, and the licensed product typeface at accessibility XXXL. On 10 August 2026 all 16 non-performance journeys passed across the complete run plus focused reruns of two corrected XCTest synchronization cases. Eleven performance tests separately cover launch, presentation, scroll, settled/peak memory, populated stores, long transcripts, repeated tab switching, and background/foreground recovery. Do not describe device-only or currently blocked checks as passing.

Development baselines and their exact result-bundle caveat live in `performance-baselines.md`. The implementation ledger in `product-improvement-audit.md` is the source of truth for remaining product and release gates.

The configured Release endpoint returned `{"status":"ok"}` from `/health` on
8 August 2026. This verifies endpoint availability only; it does not verify TLS,
registration, synchronization, coaching, or deletion through the signed iOS app.

Before each external build, manually verify on at least one physical device:

1. Clean install, anonymous registration, onboarding, relaunch persistence, dark mode, Dynamic Type, and VoiceOver labels.
2. Check-in online, check-in in airplane mode, relaunch while offline, then reconnect and confirm exactly-once synchronization.
3. Normal coaching, backend timeout, malformed response, rate limit, expired token, and fixed urgent-language response.
4. Notification allowed and denied states, daily delivery, foreground/background transitions, and timezone change.
5. Server-confirmed account deletion, Keychain removal, notification removal, and return to onboarding.
6. Upgrade from the previous TestFlight build without losing the quit plan or check-in history.
