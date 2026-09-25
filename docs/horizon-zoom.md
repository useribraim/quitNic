# Horizon — the zoom

Implementation spec. `horizon-prompts.md` describes how the art is generated.

---

## 1 · The idea

QuitNic is **one place, seen at one continuously varying scale.**

You begin impossibly far away — a valley from the height of weather. Somewhere near the
centre of the frame, too small to resolve, is a house with a lit window. The only thing that
moves the camera inward is time without nicotine.

Nothing else. Not tapping, not logging, not streaks. **Time is the only engine.**

When you finally reach the window, you pass through it, and what is on the other side is the
same valley from far away. It does not end. That is not a trick — it is the honest shape of
the thing. Nobody finishes quitting. They just keep walking, with the light on.

### What this replaces

The current model (`WorldLocation.all` in `ios/QuitNic/Views/HorizonJourneyView.swift`) is
**lateral**: five discrete places, swipe up to move between them, crossfade on arrival. The
world jumps. Progress is a slideshow of five states.

The new model is **one continuous axis**. There are no places. There is a number.

---

## 2 · Two axes, both continuous

Everything visible in the world is a function of exactly two scalars:

| Axis | Driven by | Range | Meaning |
|---|---|---|---|
| **depth** | hours nicotine-free | `0 … ∞` | how close you are |
| **light** | local time of day | `0 … 24` | what hour it is where you are |

They are orthogonal. Depth never affects colour; light never affects scale. Any feature that
wants to change the world has to express itself as one of these two, or it does not belong in
the world.

This is the whole state model. Resist adding a third.

---

## 3 · The depth model

### 3.1 Data

```swift
/// One frame of the zoom chain. Level `n + 1` is nested exactly inside level `n`,
/// occupying `nextFrame` of it.
struct ZoomLevel: Identifiable, Equatable {
    let id: Int
    /// Asset name, or a procedural seed while the art does not exist yet.
    let source: ZoomSource
    /// Unit rect within THIS image that level `id + 1` fills exactly.
    /// Midjourney's Zoom Out is uniform and centred, so this is always
    /// (0.25, 0.25, 0.5, 0.5) for a 2x chain. Kept per-level so a hand-composed
    /// level can deviate without changing the renderer.
    let nextFrame: CGRect
    /// Shown in the wayfinder when this level fills the frame. Not a place name —
    /// a scale name. "THE VALLEY", "THE HILL", "THE WINDOW".
    let name: String
}

enum ZoomSource: Equatable {
    case asset(String)
    case procedural(seed: Int)   // see §8
}
```

`stepScale` is derived, not stored: `1 / nextFrame.width`. For the whole chain it is `2`.

### 3.2 The chain and the loop

```swift
enum ZoomChain {
    static let levels: [ZoomLevel]      // exactly 10
    static var count: Int { levels.count }

    /// Unbounded. Depth is not clamped — the chain wraps.
    static func level(_ index: Int) -> ZoomLevel {
        levels[((index % count) + count) % count]
    }
}
```

Ten levels at 2× is nine doublings — a **512× traversal**, roughly an 800 m valley down to a
1.5 m window. The wrap is what makes it infinite: level 9's `nextFrame` contains a miniature
of level 0, so `level(10)` is `level(0)` and the seam is invisible. See `horizon-prompts.md` §7 for how that one image is
built; it is the only asset that cannot be produced by Zoom Out alone.

**Loop switch.** Ship it behind one flag so it can be evaluated against the alternative:

```swift
/// false → depth clamps at `count - 1` and the world goes still past two months.
static let loops = true
```

### 3.3 Depth from time

Milestones are logarithmic — 2h, 8h, 48h, 72h, 120h, 168h, 336h, 672h, 1440h — so depth is
logarithmic too. Linear time would make day one invisible and month two a blur.

```swift
enum ZoomDepth {
    /// The first milestone, in hours. Sets where the curve starts biting.
    static let h0: Double = 2

    /// Fitted so the final milestone (2 months) lands exactly on one complete
    /// traversal of the chain. The whole milestone set spans one loop; past it the
    /// second turn begins and never completes.
    static let k: Double = 1.053313   // == 10 / log2(1 + 1440 / 2)

    static func depth(hoursFree: Double) -> Double {
        guard hoursFree > 0 else { return 0 }
        return k * log2(1 + hoursFree / h0)
    }
}
```

**Unit-test this table.** Tolerance `0.001`.

| Hours | Milestone | depth | level | fraction |
|---:|---|---:|---:|---:|
| 0 | quit | 0.000 | 0 | 0.000 |
| 2 | 2 Hours | 1.053 | 1 | 0.053 |
| 8 | 8 Hours | 2.446 | 2 | 0.446 |
| 24 | *(day one)* | 3.898 | 3 | 0.898 |
| 48 | 2 Days | 4.891 | 4 | 0.891 |
| 72 | 3 Days | 5.487 | 5 | 0.487 |
| 120 | 5 Days | 6.247 | 6 | 0.247 |
| 168 | 1 Week | 6.751 | 6 | 0.751 |
| 336 | 2 Weeks | 7.795 | 7 | 0.795 |
| 672 | 4 Weeks | 8.844 | 8 | 0.844 |
| 1440 | 2 Months | **10.000** | 0 | 0.000 |
| 8760 | *(1 year)* | 12.742 | 2 | 0.742 |
| 87600 | *(10 years)* | 16.241 | 6 | 0.241 |

Milestone hours come from `ProgressCalculator.milestones`; read them from there rather than
hardcoding, and assert the table in the test. Note the set is **nine** milestones ending at
two months — the "seventeen milestones" in the old docs is stale and wrong.

Rate of change, for tuning by eye:

| Period | magnification per day |
|---|---|
| day 1 | ~1400% (≈12%/hour) |
| day 2 | ~99% |
| week 2 | ~11% |
| month 2 | ~2.5% |
| past a year | ~0.3% |

Day one moves fast because day one *is* fast. Opening the app twice on day one shows visible
travel; opening it twice in year two does not, and shouldn't.

`k` is the one number to play with. Everything else follows.

---

## 4 · The renderer

Two images on screen, ever. No more.

```
d = depth
n = floor(d)
f = d - n            // 0 ..< 1
s = stepScale        // 2

level(n)     drawn at scale  pow(s,  f)       →  1 … 2
level(n + 1) drawn at scale  pow(s, f - 1)    →  0.5 … 1
```

At `f = 0`, level *n* fills the frame and level *n+1* sits at half scale in the centre —
exactly the region it depicts. At `f = 1`, level *n*'s centre quarter fills the frame and
level *n+1* is at 1:1 over it, pixel-identical. Increment `n`, reset `f`, continue. There is
no transition to animate.

### 4.1 Hiding the seam

Do **not** cross-fade on opacity — that produces a soft double image through the middle of
every step. Level *n+1* is always drawn on top, always fully opaque, with a **feathered alpha
mask** on its own edge:

```swift
.mask {
    RoundedRectangle(cornerRadius: 0)
        .fill(.white)
        .blur(radius: geo.size.width * 0.035)   // feather ≈ 3.5% of frame width
        .padding(geo.size.width * 0.02)         // pull the soft edge inside the bounds
}
```

The feather hides the ring where Midjourney's outpainting meets the original. Tune the two
numbers by eye against real art — too tight and the seam shows, too loose and the centre
looks vignetted.

### 4.2 Order of operations

This order is not negotiable; getting it wrong is the most likely way to make it look cheap.

```
1. level(n)      scaled
2. level(n+1)    scaled, feather-masked        ← composited into the same drawingGroup
3. .drawingGroup()                              ← rasterise the world once
4. light grade                                  ← §5, over the composite, not inside it
5. GrainOverlay                                 ← fixed size, NEVER scaled
6. bottom scrim for the tab bar
7. UI layer
```

**Grain must not magnify.** It is on the glass, not in the world. If grain scales with depth
the whole thing reads as a photograph being zoomed rather than a place being approached. One
opacity everywhere — pick a single value (`0.05` is the current world value and is close) and
delete the other two.

### 4.3 Motion and performance

- Depth changes animate with `.interpolatingSpring(stiffness: 40, damping: 12)` for
  navigation pushes, and are applied **directly with no animation** for the ambient
  time-driven drift — that one is already slow enough to be its own animation.
- `drawingGroup()` on the composited world only. Not on the UI layer.
- At most **three** decoded images resident: `n`, `n+1`, and one prefetch in the direction of
  travel. Evict the rest.
- Target 60fps during a Journey scrub on iPhone 15 and newer.
- `accessibilityReduceMotion`: depth changes apply instantly, no spring, no ambient drift
  animation. The world still shows the correct depth — it just never animates to it.

---

## 5 · The light axis

`HorizonScene.arc` (17 hand-tuned sky/land colour pairs) is currently indexed by *location*.
That is wrong now — a gradient sky cannot exist once the camera is inside a window.

Keep the colours. Change what indexes them.

```swift
enum HorizonLight {
    /// The existing 17 entries, reused as keyframes across a 24-hour day.
    /// Interpolated, not selected: light is continuous like depth is.
    static func grade(at date: Date, calendar: Calendar = .current) -> ColorGrade
}

struct ColorGrade {
    let tint: Color
    let opacity: Double
    let blendMode: BlendMode   // .multiply for night, .overlay for warm hours
}
```

Applied once, over the composited world (step 4 above), so both levels grade identically. If
it is applied per-level the seam becomes visible the moment the grade is anything but neutral.

The payoff: **3am looks like 3am.** That is the hardest hour to stay quit, and the app should
know what time it is without being told.

Do not tie light to depth. Someone at depth 8 at noon and someone at depth 2 at noon are
standing in the same daylight, at different distances.

---

## 6 · Navigation is depth

There are no screen transitions. Everything is the camera moving on the same axis.

| Screen | Depth | Motion |
|---|---|---|
| **Today** | `depth(hoursFree)` exactly | ambient, no animation |
| **Journey** | scrubbable `0 … earned + 1.0` | direct manipulation, rubber-band past the ends |
| **Coach** | `earned + 2.0` | push in over ~1.2s, ease-in-out |
| **Rescue** | `0`, then home | see §7 |
| **Settings** | *leaves the world* | plain sheet over `HorizonBackdrop`; it is utility, don't force it |

**Journey** replaces the discrete swipe-to-travel gesture. Vertical drag maps to depth
continuously — roughly one level per 260pt of travel, matching the current gesture's feel.
No settling, no snapping to a place. You may scrub one full level past where you have earned,
and no further; past that, rubber-band with the existing `0.18` resistance factor. Release
anywhere and it stays there; leaving the tab returns to earned depth.

The **wayfinder** becomes a depth ruler: a vertical scale on the right edge with a tick per
level, the current position marked, milestone depths marked differently, and everything past
`earned` drawn at low contrast. It replaces `HorizonJourneyView.wayfinder`.

**Milestones are not screens.** Delete the `fullScreenCover` on `MilestoneCelebrationView`.
A milestone is a depth at which something resolves into view. Crossing one:

- a soft haptic (`UIImpactFeedbackGenerator(style: .soft)`, already imported)
- the milestone's `celebration` string fades into the sky for ~6 seconds, then fades out
- nothing to dismiss, nothing to tap

If someone was not looking, they missed it, and that is correct — the world does not wait for
an audience. `MilestoneAcknowledgement` still records what has been crossed so the copy is not
repeated.

---

## 7 · Rescue pulls back

This is the centre of the design. Build it first after the renderer.

A craving is the one moment where the right move is to **lose** ground on purpose.

```
t = 0s      camera begins retreating from earned depth toward 0.
            Soft haptic. Screen carries one word: "Breathe."
            No buttons. Nothing to decide. Nothing to dismiss.

t = 0–6s    the pull-back. easeOut. Six seconds to travel the whole chain, so it
            reads as falling away rather than scrolling.

t = 6–110s  held at depth 0. The whole valley. Whatever is happening is one pixel
            wide and somewhere near the middle.
            Breathing runs on the LIGHT axis, not depth: warmth rises on the inhale,
            cools on the exhale, 4s phases. Reuse `breathPhaseSeconds` in
            `CheckInView.swift`, which is already 4.0.
            Depth drifts outward imperceptibly, 0 → -0.15, and never visibly stops.

t = 110–120s  return to earned depth. easeInOut, ~10s. You come home.

t = 120s+   only now: trigger, outcome, the questions.
```

The existing flow asks for a trigger and an intensity rating **before** the breathing. That is
asking someone mid-craving to fill in a form. Reverse it. `Step.welcome` and `Step.assess`
move after `Step.reset`; `startingIntensity` is either dropped or asked retrospectively
("how bad was it?"), which is more honest anyway — people are bad at rating a thing they are
inside of.

One escape hatch, present throughout at low contrast: a quick-log affordance for someone who
just wants to record a slip and leave. That path already exists as `Step.quickLog`.

Zoom in is progress. Zoom out is perspective. That is the whole grammar of the app and this
screen is where it pays.

---

## 8 · Build before the art exists

The art is a Midjourney session that has not happened yet. Do not wait for it.

Ship `ZoomSource.procedural(seed:)` and a `ProceduralLevel` view that draws a deterministic
vector scene honouring the same nesting contract:

- a full-bleed background in a seeded colour from the Horizon palette
- a visible border ring so the level boundary is obvious during development
- the level index rendered large, so you can see which level you are on
- a clearly marked rectangle at exactly `nextFrame` — the next level must land inside it
- some fine detail near the centre so it is possible to judge whether the scale ramp is smooth

Build and test the entire renderer, the depth curve, Journey scrubbing and Rescue against
this. When the art arrives, the only change is `ZoomChain.levels` swapping
`.procedural(seed:)` for `.asset(name:)`. Nothing else moves.

Keep the procedural path in the shipped binary behind a launch argument
(`-zoom-procedural`) — the UI tests should run against it, because they must not depend on
15 MB of artwork loading correctly.

---

## 9 · Deletions

Remove outright. These are not deprecations; leaving them is what produced two design systems
in the first place.

| Path | Why |
|---|---|
| `ios/QuitNic/Views/JourneyView.swift` | legacy list-of-cards journey, old palette |
| `WorldLocation` + `WorldLocation.all` | replaced by `ZoomChain` |
| `HorizonJourneyView.travelGesture`, `dragDestination`, `furthestVisitable`, `houseLight`, `pan(in:)`, `screenPoint(in:)` | discrete travel; no longer meaningful |
| `HorizonScene.arc` as an indexed array | becomes `HorizonLight.grade(at:)`, colours retained |
| `Assets.xcassets/HorizonLandscape.imageset` | zero references; archived under `musorka/source-plates` |
| `DashboardView.legacyDashboard` | dead code, old palette |
| `MilestoneCelebrationView` full-screen cover | milestones resolve in-world (§6) |

Deferred but coming: `QuitNicTheme` and everything still reading from it — `OnboardingView`,
`SettingsView`, and the 41 references inside `CheckInView`. Onboarding is the first screen
anyone sees and it is currently a plain `Form` in the old teal palette that fails its own
contrast audit. It is not in this spec but it is the next one.

---

## 10 · What survives

- `insideHorizonWorld(_:)` — same call site, new engine underneath
- `GrainOverlay` — one opacity, applied outside the scaled stack
- `HorizonTheme.accent` — `rgb(255, 64, 26)`. It is the lit window, it is the roof of the
  house, and it is the Rescue button. It appears **nowhere else**. Navigation is not an
  emergency; `RootView` already enforces this and should keep doing so.
- `HorizonType.display / body / counter` — the single registration point for the licensed
  Satoshi variable face; counters deliberately remain monospaced where timing needs it.
- `HorizonBackdrop` — still needed for Settings and any sheet that leaves the world

---

## 11 · Composition rules for the art

Full generation method is in `horizon-prompts.md`. The constraints the *renderer* imposes:

- **The zoom target is always dead centre.** Midjourney's Zoom Out is uniform and centred;
  there is no version of this where the subject sits left of centre. The old rule about
  keeping the subject at x = 0.35–0.5 is void.
- **Type lives in a ring.** Headline at 15–30% down, counter at 78–88%. The middle band
  belongs to the world.
- **Nothing high-contrast at the 25% / 75% boundary** — that is where the previous level's
  feathered edge lands.
- **Every level is seen twice**: once as a full frame, once as the centre quarter of its
  parent. It has to look deliberate at both scales. This is the constraint that will cost the
  most regenerations.
- 1290 × 2796, HEIC, ~1.2 MB each. Ten levels ≈ 12 MB, down from the current 25 MB of PNG.

---

## 12 · Acceptance criteria

**Depth**

- `depth(0) == 0`; the §3.3 table matches within `0.001`, read from `ProgressCalculator.milestones`
- depth is monotonic and unbounded; `ZoomChain.level(_:)` wraps correctly for negative and
  large indices

**Renderer**

- scrubbing depth `0 → 10` continuously shows no seam, no flash, no double image. Snapshot
  test at `f ∈ {0.0, 0.25, 0.5, 0.75, 0.99}` for at least two consecutive levels
- with `loops = true`, crossing depth `10.0` is pixel-continuous with depth `0.0`
- grain does not change apparent size at any depth
- at most three decoded images resident at any time
- 60fps sustained during a full Journey scrub, iPhone 15 and newer

**Rescue**

- no interactive control on screen for the first 6 seconds except the quick-log affordance
- trigger and outcome are never requested before `t = 120s`
- the full sequence completes without input and returns to earned depth

**Accessibility**

- Reduce Motion: no animated depth travel anywhere, including Rescue's pull-back (it cuts)
- the world stays `accessibilityHidden(true)`; depth is described in the wayfinder's label,
  not the artwork's
- accessibility-XXXL: the headline ring at 15–30% and the counter at 78–88% must not collide;
  the middle band may be encroached on but never fully covered

---

## 13 · Open questions

Not for implementation — for the person holding the design.

1. **What is at the centre?** The spec assumes a lit window. A door, or a figure, changes what
   arrival means.
2. **Does the loop read as profound or as a bug?** It has to be unmistakably deliberate. If
   the composite in `horizon-prompts.md` §7 does not sell it, `loops = false` is the honest
   fallback and the world simply goes still at two months.
3. **Does Coach really live inside the house?** Pushing past earned depth means showing
   somewhere you have not reached yet. That might be a gift, or it might spoil the arrival.
4. **The display face.** Resolved with the licensed upright Satoshi variable font. The app
   ships one font file and its ITF Free Font License; there is no user-facing style picker.
