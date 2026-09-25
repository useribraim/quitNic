# QuitNic minimalism and performance: 100 papercuts

This list comes from exercising seeded Today, Journey, Rescue, Quick Log, Coach,
History, and Settings flows on an iPhone simulator. The order is intentional:
remove duplicated interface and render work before adding new polish.

Status: **done** is in the first reduction pass; **next** is a concrete follow-up.

| # | Area | Reduction | Status |
|---:|---|---|---|
| 1 | Today | Remove the redundant `QuitNic` wordmark; the tab and app context already identify the product. | done |
| 2 | Today | Keep Settings as a plain toolbar icon instead of a decorated circular control. | done |
| 3 | Today | Reduce the streak headline from 58 pt to a calmer 48 pt ceiling. | done |
| 4 | Today | Put savings and streak context on one line instead of two labels. | done |
| 5 | Today | Keep the next milestone to one tappable, truncated line. | done |
| 6 | Today | Remove the weekly “moments noticed” sentence from the support panel. | done |
| 7 | Today | Remove the support row: Coach belongs in the persistent third tab and Quick Log stays inside the craving flow. | done |
| 8 | Today | Remove the explanation of what each support button does; labels and accessibility hints already do that. | done |
| 9 | Today | Remove the support panel’s nested border and heavy fill. | done |
| 10 | Today | Collapse the latest check-in to status, trigger, and optional offline icon. | done |
| 11 | Journey | Replace the 196 pt image hero with a compact textual progress header. | done |
| 12 | Journey | Merge elapsed time, checkpoint count, and progress into one surface. | done |
| 13 | Journey | Compress the “up next” card and remove its explanatory percentage sentence. | done |
| 14 | Journey | Remove the redundant “All checkpoints” heading. | done |
| 15 | Journey | Remove the decorative vertical roadmap rail. | done |
| 16 | Journey | Reduce milestone row padding and icon size. | done |
| 17 | Journey | Reserve the accent border for the next checkpoint only. | already |
| 18 | Journey | Remove reached-stamp spring animations and row-state animations. | done |
| 19 | Journey | Collapse reached checkpoints into a disclosure summary after the user has passed five. | done |
| 20 | Journey | Initially show only the next three future checkpoints, with a “show all” action. | done |
| 21 | Quick Log | Remove the marketing eyebrow, 20-second badge, giant two-line headline, and intro paragraph. | done |
| 22 | Quick Log | Use the navigation title as the only screen title. | done |
| 23 | Quick Log | Turn “use last details” into a compact row instead of a promotional card. | done |
| 24 | Quick Log | Keep intensity label, value, and control in one surface. | already |
| 25 | Quick Log | Remove the neutral-value explanation below the intensity control. | done |
| 26 | Quick Log | Move optional coping actions behind a disclosure until requested. | done |
| 27 | Quick Log | Show recently used triggers before the full trigger list. | done |
| 28 | Quick Log | Replace two large outcome cards with a compact two-choice control. | done |
| 29 | Quick Log | Pin Save above the keyboard and bottom safe area. | done |
| 30 | Quick Log | Remove selection haptics from every metadata chip. | done |
| 31 | Coach | Replace the live, multi-image zoom background with the shared lightweight gradient. | done |
| 32 | Coach | Remove the 1.2-second camera-push animation when Coach opens. | done |
| 33 | Coach | Replace the large hero and repeated scope text with one short sentence. | done |
| 34 | Coach | Make suggested prompts compact rows with no extra section heading. | done |
| 35 | Coach | Make Rescue a small secondary action instead of a full-width red button. | done |
| 36 | Coach | Avoid animating the whole screen when keyboard focus changes. | done |
| 37 | Coach | Cache parsed assistant Markdown per saved message instead of rebuilding it on every render. | done |
| 38 | History | Default to the last seven days, with older entries available on demand. | done |
| 39 | History | Replace the four-way segmented filter with a compact menu. | done |
| 40 | History | Replace the large patterns section with one inline insight. | done |
| 41 | Typography | Use the licensed Satoshi variable face; remove the three-style picker and preview card. | done |
| 42 | Typography | Ship one upright variable font plus its licence, not a static-weight family or unlicensed reference fonts. | done |
| 43 | Rendering | Remove the tiled grain overlay from forms and reading screens. | done |
| 44 | Rendering | Remove the second full-screen compositing group from the landscape renderer. | done |
| 45 | Rendering | Remove runtime grain from the landscape; the source plates already contain texture. | done |
| 46 | Assets | Downsample landscape plates to the maximum shipped device resolution and remeasure decoded memory. | done |
| 47 | Startup | Defer non-visible sync and notification refresh until after the first interactive frame. | done |
| 48 | Navigation | Remove the hidden global swipe gesture and haptic; use the visible Today/Journey tabs. | done |
| 49 | Settings | Hide developer tools unless a dedicated developer launch argument is present. | done |
| 50 | Quality | Add launch, Quick Log, Journey scroll, and memory budgets to CI and reject regressions above 20%. | done |
| 51 | Startup | Delay foreground maintenance until the first interactive frame has rendered. | done |
| 52 | Startup | Do not reschedule identical milestone notifications on every foreground. | done |
| 53 | Startup | Reschedule the inactivity nudge at most once per calendar day. | done |
| 54 | Data | Stop querying the latest slip independently in both Root and the tab container. | done |
| 55 | Data | Fetch only the one active quit plan instead of observing an unconstrained plan array. | done |
| 56 | Sync | Skip authentication and network work when the outbox and deletion flags are empty. | done |
| 57 | Sync | Batch outbox mutations and save once instead of saving after each delivered operation. | done |
| 58 | Sync | Give outbox recovery a per-foreground operation budget so a large queue cannot monopolise launch. | done |
| 59 | Sync | Move payload encoding and decoding off the main actor. | done |
| 60 | Sync | Avoid scanning every pending operation to cancel one check-in; use a predicate fetch. | done |
| 61 | Assets | Remove the now-unused Grain view and asset from the shipping catalogue. | done |
| 62 | Assets | Ship viewport-bounded source plates so the catalogue cannot decode oversized originals; avoid a custom ImageIO loader. | done |
| 63 | Assets | Downsample 1289 × 2796 plates to the 1206 × 2622 maximum shipped viewport. | done |
| 64 | Assets | Re-encode oversized JPEGs at a measured quality floor and compare visual difference. | done |
| 65 | Assets | Keep one bounded catalogue: Today's looping chain can reach all five plates, so none are honestly Journey/Rescue-only. | done |
| 66 | Rendering | Instantiate the incoming landscape only when the dissolve actually begins. | done |
| 67 | Rendering | Quantise time-of-day grading to the minute so seconds do not invalidate the canvas. | done |
| 68 | Rendering | Remove the vignette when the selected source plate already carries edge falloff. | done |
| 69 | Rendering | Precompute colour-grade keyframes rather than allocating tint colours during body evaluation. | done |
| 70 | Rendering | Pause all landscape animation and timers while Reduce Motion or Low Power Mode is active. | done |
| 71 | Today | Use an adaptive clock: minute updates early, hourly later, daily after the final milestone. | done |
| 72 | Today | Fetch only the recent check-ins the screen can display, not 50 records. | done |
| 73 | Today | Remove milestone haptics and long fade animations from passive progress updates. | done |
| 74 | Today | Remove the hidden upward Journey gesture; the visible tab is sufficient. | done |
| 75 | Today | Hide the latest-check-in surface once it is old enough to stop being actionable. | done |
| 76 | Navigation | Remove the global horizontal swipe recogniser that competes with sliders and scroll views. | done |
| 77 | Navigation | Remove the automatic haptic every time Journey becomes selected. | done |
| 78 | Navigation | Use static tab icons rather than recomputing filled variants from selection. | done |
| 79 | Journey | Do not attach scroll-position state until an actual restoration target exists. | done |
| 80 | Journey | Move the medical timeline disclaimer behind a compact information action. | done |
| 81 | Journey | Show one reached-checkpoint summary instead of a card for every old checkpoint. | done |
| 82 | Journey | Render only the next three future checkpoints until “Show all” is requested. | done |
| 83 | Journey | Stop recomputing the full journey array multiple times per body pass. | done |
| 84 | Journey | Remove the secondary detail line from collapsed reached rows. | done |
| 85 | Journey | Keep expanded long-form copy mounted only for the selected milestone. | already |
| 86 | Quick Log | Reduce trigger chips to recent choices plus a single “More” disclosure. | done |
| 87 | Quick Log | Keep optional coping actions collapsed until requested. | done |
| 88 | Quick Log | Remove selection haptics from trigger and outcome metadata. | done |
| 89 | Quick Log | Replace the large outcome cards with a compact two-choice control. | done |
| 90 | Quick Log | Return immediately after an ordinary quick save instead of showing a completion interstitial. | done |
| 91 | History | Query a bounded first page and load older history on demand. | done |
| 92 | History | Default to seven days and replace the segmented control with a compact menu. | done |
| 93 | History | Replace the multi-row patterns card with one inline insight. | done |
| 94 | History | Remove duplicate context-menu actions when swipe actions already expose edit and delete. | done |
| 95 | Coach | Stop animating transcript autoscroll for every message insertion. | done |
| 96 | Coach | Hide the microphone until voice input has been deliberately enabled. | done |
| 97 | Coach | Replace three full-width prompts with horizontally scrolling chips. | done |
| 98 | Settings | Remove the separate About section and place version in a lightweight footer. | done |
| 99 | Settings | Hide the Sync section when everything is healthy; surface it only for pending work. | done |
| 100 | Quality | Add an automated shipped-asset manifest so unused images and bundle growth fail review. | done |

## Acceptance targets

- Today exposes one primary action and one progress story; Coach is the third persistent tab.
- Quick Log reaches Save with materially less scrolling on a standard iPhone.
- Coach opens without decoding or animating the five-plate landscape chain.
- Reading surfaces do not tile a full-screen grain texture.
- The font choice adds no bundle weight unless a single licensed variable font replaces
  the native face.
- Existing unit behavior remains green and changed UI flows remain reachable by their
  accessibility identifiers.
