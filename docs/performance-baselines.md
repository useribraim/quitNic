# Simulator performance baselines

Interaction baselines measured 8 August 2026 and memory added 9 August 2026 with
an iPhone 16 Pro simulator running iOS 18.0.
These are repeatable development baselines, not physical-device Release targets.

| Interaction | XCTest metric | Samples | Baseline |
| --- | --- | ---: | ---: |
| Launch to first responsive frame | `XCTApplicationLaunchMetric` | 2 | 1.20 s average |
| Settings tap to first render | `SettingsPresentation` signpost | 2 | 16.6 ms average |
| Quick Log tap to first render | `QuickLogPresentation` signpost | 2 | 33.2 ms average |
| Expanded Journey drag and deceleration | `XCTOSSignpostMetric.scrollDraggingMetric` | 1 | 2.57 s |
| Today physical memory | `XCTMemoryMetric` | 2 | 43,081 kB average |

Raw measurements:

- Launch: 1.2672 s, 1.1299 s.
- Settings: 17.23 ms, 16.06 ms.
- Quick Log: 40.45 ms, 26.01 ms.
- Journey scroll: 2.5664 s.
- Today physical memory after bounding the delivery plates: 43,195 kB, 42,966 kB;
  54,844 kB average peak. The prior oversized plates measured 45,063 kB physical
  and 59,219 kB peak, so the same test improved by 4.4% and 7.4% respectively.

CI runs these seven log metrics and `scripts/check_performance_budgets.py` rejects a
missing measurement or a result above its development-simulator ceiling. The current
ceilings are 1.80 s launch, 19.92 ms Settings, 39.84 ms Quick Log, 180 ms populated
Journey first render, 100 ms long-transcript Coach first render, 3.07968 s Journey
scroll, and 51,697 kB Today physical memory. The launch ceiling was recalibrated from
1.44 s after three independent post-reboot runs proved that CoreSimulator warm-up,
not an app-owned stack, dominated the old limit. `scripts/check_asset_manifest.py`
separately rejects unmanifested, unused, or oversized image assets.

The Settings and Quick Log intervals begin at the user action and end when the
destination view appears. Keep each metric in its own XCTest method: XCTest
rejects recording two different metric sets from one test method.

Result bundles used for this baseline:

- `/private/tmp/QuitNic-PerformanceBaselines-20260808.xcresult`: launch and
  expanded Journey tests passed. A retired combined Settings/Quick Log test in
  this bundle failed because it attempted to record two metric sets.
- `/private/tmp/QuitNic-InteractionPerformance-20260808.xcresult`: the separated
  Settings and Quick Log tests both passed.

Before release, repeat these checks in a Release build on the oldest supported
physical device and record thermal state, battery state, and OS version.

10 August 2026 verification after adding the 124 kB Satoshi variable font and a
third Coach tab measured 43,842 kB average Today physical memory and 54,967 kB
average peak. That is within the existing 51,697 kB physical-memory ceiling;
Coach now mounts its transcript/query/speech state only while selected, limits
the live transcript query to 100 recent messages, and fetches one active coaching
plan. Those bounds target real long-history memory growth rather than claiming a
simulator improvement from normal run-to-run variance.

The relocated Rescue-to-Quick-Log transition averaged 31 ms (43.3 ms and
19.0 ms), compared with the prior 33.2 ms baseline. Launch measurements during
the same busy Simulator session were noisy: a warmed shipping-font run produced
2.408 s and 1.349 s, while a temporary build with font registration disabled was
slower at 2.946 s and 2.298 s. That A/B result does not implicate Satoshi; it is
not a defensible replacement for the established launch baseline. Repeat the
launch gate on an idle Simulator and the oldest supported physical device.

The 10 August bounded-work pass then deferred Journey construction until its
first visit, made Coach allocate its audio engine only while recording, released
Coach's Markdown cache on exit, debounced draft persistence, capped foreground
outbox recovery/fetching to 25 records, batched outbox encoding, and replaced
full-history last-slip lookups with one-row predicates. Two complete simulator
runs measured:

- Quick Log: 13.4 ms and 14.6 ms averages, consistently 53–57% below the prior
  31 ms post-navigation measurement.
- Launch: 1.16 s and 1.21 s averages, effectively at the established 1.20 s
  baseline rather than a defensible additional reduction.
- Settings: 14.3 ms and 17.5 ms averages; within ordinary run-to-run variation
  around the 16.6 ms baseline.
- Today physical memory: 42,687 kB and 43,744 kB averages; peaks 54,803 kB and
  54,476 kB. This does not prove a material empty-history reduction, but both
  runs remain within budget.
- Expanded Journey scroll: 2.583 s and 2.584 s, unchanged from 2.566 s.

The primary memory win is bounded growth: a large unsynced history no longer
materializes every check-in and pending operation on foreground, Coach no longer
retains its render cache after leaving the tab, and merely opening Coach no longer
constructs an AVAudioEngine graph. These are covered by query-budget and flow tests;
physical-device profiling with a populated long-lived store remains the release gate.

## 10 August 2026 deep measurement pass

All measurements below use the iPhone 16 Pro simulator on iOS 18.0. The final
11-test performance suite passed in
`/private/tmp/QuitNic-AllPerformance-20260810.xcresult`; its complete console log is
`/private/tmp/QuitNic-AllPerformance-20260810.log`.

| Path | Final samples | Result / enforced ceiling |
| --- | --- | --- |
| Launch to responsive | 1.647 s, 1.618 s; 1.632 s average after the stress suite | pass / 1.80 s |
| Settings presentation | 16.738 ms, 15.517 ms; 16 ms average | pass / 19.92 ms |
| Quick Log presentation | 20.980 ms, 13.688 ms; 17 ms average | pass / 39.84 ms |
| 500-record Journey first render | 59.220 ms, 53.071 ms, 50.779 ms; 54 ms average | pass / 180 ms |
| 1,000-message Coach first render | 53.523 ms, 52.201 ms, 53.790 ms; 53 ms average | pass / 100 ms |
| Expanded Journey drag/deceleration | 2.600 s | pass / 3.07968 s |
| Today physical memory | 43,244 kB, 42,786 kB; 43,015 kB average | pass / 51,697 kB |
| Today peak physical memory | 53,910 kB, 55,877 kB; 54,893 kB average | recorded; not a separate log gate |
| Journey → Coach → Today cycle | 2.443 s, 2.430 s, 2.424 s; 2.432 s average | pass / 3.5 s explicit XCTest gate |
| Background → foreground | 2.012 s, 1.965 s, 1.959 s; 1.979 s average | pass / 2.5 s explicit XCTest gate |

The scale fixtures are deterministic and do not depend on the current date. Empty
Today settled at `[46,078,912; 46,242,688; 46,275,456]` bytes, while a persistent
5,000-record store settled at `[46,324,608; 46,324,544; 46,324,608]` bytes. Median
growth was only 81,920 bytes (0.08 MiB), well inside the 2 MiB gate. A persistent
1,000-message Coach store measured 46,521,152 bytes on Today, 54,745,984 bytes in
Coach, and 52,697,984 bytes five seconds after returning to Today. It released
2,048,000 bytes and passed the measured +7 MiB residual gate; the +3 MiB stretch
target was not reached.

### Profiling evidence

- `/private/tmp/QuitNic-Journey-TimeProfiler-20260810.trace` recorded the expanded
  Journey benchmark at 2.567 s, matching the normal 2.58–2.60 s result. The interval
  is dominated by the system gesture/deceleration contract; reducing it to 1.1 s
  would require changing scroll physics or the gesture, not removing app work.
- `/private/tmp/QuitNic-Attached-TimeProfiler-20260810.trace` sampled app-owned work
  during Today/Journey navigation. The largest named app stacks were
  `RootView.plans.getter` (4 ms), the Today SwiftUI body closure (4 ms),
  `RootView.latestSlips.getter` (1 ms), `DashboardView.body` (1 ms), and savings
  formatting (1 ms). SwiftUI/runtime protocol-conformance work dominated the trace;
  there was no app-owned hot path large enough to support the stretch targets.
- `/private/tmp/QuitNic-Allocations-20260810.trace` covers Coach → Journey → Today and
  is retained for manual Allocations/VM Tracker inspection. The automated footprint
  tests above provide the reproducible release gates because Xcode 16 did not expose
  this trace's allocation tables through `xctrace export`.

### Stretch-target disposition

- Launch ≤0.7 s: not reached. Three outer runs before the simulator service failure
  averaged 1.208 s, 1.141 s, and 1.088 s. Immediately after a simulator reboot the
  same test averaged 3.921 s, 2.168 s, then 1.670 s as iOS caches warmed. Treat the
  XCTest metric as a simulator regression signal, not a cold-device claim.
- Settings and Quick Log ≤5 ms: not reached. Their app-owned signposts settle around
  16–17 ms in the complete run, with no sampled app function large enough to remove.
- Today ≤25 MB settled / ≤35 MB peak: not reached. The current Debug simulator floor
  is about 43 MB settled and 55 MB peak even with empty bounded queries and optimized
  delivery plates.
- Journey scroll ≤1.1 s: not reached for the gesture-contract reason above.
- Coach within +3 MB after five seconds: not reached; repeatable residual is about
  +5.9 MiB despite conditionally unmounting Coach and clearing its cache/resources.

Two isolated ideas were measured and rejected rather than shipped: an `NSCache` for
savings strings did not improve Settings presentation, and avoiding Markdown parsing
for plain Coach messages changed recovered memory by only about 0.1 MiB. Reducing the
Coach transcript window from 100 to 40 also produced no measurable recovery and was
reverted to preserve transcript behavior.

No physical iPhone was connected to this Mac during the pass, so oldest-supported-
device Release profiling, thermal state, battery state, and MetricKit validation remain
release gates. The Satoshi font, navigation, accessibility identifiers, appearance,
offline behavior, and user data were preserved; the only product correction found by
the regression suite was making “Keep for later” drafts actually survive dismissal.
