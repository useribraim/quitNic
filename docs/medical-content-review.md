# Medical content review

Last evidence check: 7 August 2026

QuitNic provides general educational guidance and is not a diagnostic or treatment
service. All in-app milestone wording uses conditional language and the Journey screen
states that timelines are common patterns rather than personal predictions.

## Product boundary

- Cigarette plans may show smoking-specific recovery information.
- Vape, nicotine-pouch, and Other plans show only nicotine-withdrawal and behaviour-cue
  guidance. They must never mention carbon monoxide, smoke-free recovery, bronchial
  tubes, taste/smell recovery, or smoking circulation claims.
- Automated coverage in `JourneyTests` guards that separation.

## Evidence used

- NHS Better Health, *Benefits of quitting smoking*: carbon monoxide leaves the body,
  taste and smell improve, breathing may feel easier, and circulation can improve on
  the published smoking timeline.
  https://www.nhs.uk/better-health/quit-smoking/why-quit-smoking/benefits-of-quitting-smoking/
- NHS Better Health, *Managing nicotine withdrawal symptoms*: symptoms are commonly
  strongest in the first week, especially the first three days, and average three to
  four weeks while individual experience varies.
  https://www.nhs.uk/better-health/quit-smoking/staying-smoke-free/managing-nicotine-withdrawal-symptoms/
- US National Cancer Institute, *Handling nicotine withdrawal and triggers*: common
  symptoms, their variable course, and practical coping approaches.
  https://www.cancer.gov/about-cancer/causes-prevention/risk/tobacco/withdrawal-fact-sheet

## Release gate

This evidence review reduces unsupported product claims but does not replace human
clinical review. Before App Store release, a qualified smoking-cessation clinician must
approve the final strings in `ProgressCalculator.milestones(for:)`; record their name,
date, requested edits, and approval here.
