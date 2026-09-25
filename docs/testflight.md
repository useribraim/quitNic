# TestFlight release checklist

- Install current full Xcode, set a unique bundle identifier, select the Apple Developer team, and increment build/version values.
- Create the matching App Store Connect record and complete the privacy-policy URL, app privacy questionnaire, age rating, category, support URL, and export-compliance answers.
- In Organizer, confirm the archive contains `PrivacyInfo.xcprivacy`, generate its privacy report, and ensure App Store Connect answers match the manifest's Health, Audio Data, Other User Content, and Device ID declarations.
- Confirm the archive reports `ITSAppUsesNonExemptEncryption = NO`; QuitNic uses operating-system HTTPS/Keychain rather than proprietary cryptography.
- Confirm the production API uses HTTPS and complete the physical-device smoke test in `docs/testing.md`.
- Archive a Release build, validate it, upload it, and confirm processing completes without symbol or entitlement warnings.
- Add beta description: “QuitNic helps testers set a quit date, track cravings and progress, receive reminders, and request brief AI-assisted behavioural coaching. It is not medical care.”
- Add review notes explaining anonymous device registration, how to reach each feature, the AI safety boundary, data deletion, and that no login credentials are required.
- Create an external-testing group, add the build, complete Beta App Review, invite a small named tester group first, and collect crash/feedback results.
- After the build is stable and approved, enable the public TestFlight link with a conservative tester limit. Verify a clean install through the public link on a device not associated with development.

Do not publish a TestFlight URL or claim external distribution on a résumé until Apple has approved the beta and an external tester has successfully installed the current build.
