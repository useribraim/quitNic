# Privacy and safety notes

QuitNic stores the quit plan, craving events, and recent coaching messages. The quit plan and full local history remain in SwiftData. Synchronized records are associated with a random device account, not an email address or advertising identifier.

Coaching requests send the current message and at most ten recent turns to the configured AI provider. The app must disclose this processing in its privacy policy and App Store privacy answers. Logs must never contain authorization headers, message bodies, API keys, or database credentials.

QuitNic is behavioural support, not medical care. It does not diagnose, prescribe, recommend medication doses, or replace a clinician. Urgent language returns a fixed escalation message. Legal/privacy review is required before public distribution; this document is an engineering inventory, not legal advice.

Account deletion removes the server account and cascades through its tokens, quit plan, check-ins, and coaching messages, then removes the local store, Keychain token, and notifications.

