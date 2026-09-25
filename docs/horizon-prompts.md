# Horizon — generating the zoom chain

Ten nested images. Each one contains the next at exactly half scale, dead centre. Together
they are a single continuous approach from the whole valley down to one lit window, and then
back to the whole valley again.

Read `horizon-zoom.md` first — it defines what the renderer expects. This file is the
Midjourney session that produces it.

---

## 1 · The order inverts

The previous version of this document generated eight independent compositions from distant to
close. **Independent images cannot nest.** Two separately generated pictures of the same valley
at different distances will not line up, and no amount of style-referencing will make them.

The chain has to be produced by outpainting, which means generating the **innermost frame
first** and pulling back:

```
generate L9 (the window)  →  Zoom Out 2×  →  L8  →  Zoom Out 2×  →  L7  →  …  →  L0
```

Midjourney's Zoom Out places the source image dead centre at exactly half linear scale and
paints the surrounding ring. Registration is free — you cannot get it wrong. Then reverse the
files: the last thing you generate is level 0, the first thing anyone sees.

Ten levels at 2× is nine doublings, a **512× traversal** — roughly an 800 m valley down to a
1.5 m window.

---

## 2 · Before you start

**One session.** Style drifts between sessions and the whole effect depends on this reading as
one continuous place. Budget two to three hours.

**Style reference, attached once and never removed.** Upload
`musorka/source-plates/legacy-horizon-landscape.jpg`, set it to **Style**, weight **250**.
It is the archived palette reference, not a shipping asset.

**No Omni reference.** The old workflow used one to keep the cottage consistent. It is not
needed here and it actively hurts: the cottage's consistency now comes from the chain itself,
since every level literally contains the previous one. An Omni reference will fight the
outpainting and paste extra cottages into the ring.

**Aspect ratio is set once, at L9, and never touched again.** Zoom Out preserves it. If you
change `--ar` mid-chain the nesting breaks and you start over. Use `--ar 9:19`.

**Custom Zoom, not the Zoom Out button.** The plain "Zoom Out 2x" button reuses the previous
prompt, which will keep describing a window when you are three levels out into a field. Use
**Custom Zoom**, set `--zoom 2`, and paste the new prompt for that level.

---

## 3 · The shared tail

Every prompt below ends with this. It is identical every time — paste it unchanged.

```text
airbrushed digital gouache, heavy fine film grain, low sun from the left, flat deep cobalt blue sky, luminous green grass with soft bands of light and dark olive --ar 9:19 --v 7 --s 180 --chaos 4 --sw 250 --no text, watermark, logo, letters, ui, interface, buttons, people, figures, animals, roads, cars, fences, power lines, signage, border, frame, vignette, multiple buildings
```

`border, frame, vignette` matter more than usual here — Midjourney likes to draw a decorative
edge at an outpainting seam, and that is exactly where the renderer's feather mask sits.

---

## 4 · The ten levels

Generate **bottom to top**. L9 first, plain prompt, no zoom. Everything after it is Custom
Zoom at `--zoom 2` on the upscale of the level below.

### L9 · THE LIGHT — generate this one first

Plain imagine, no zoom, no references except Style.

```text
extreme close view of a single small window in a whitewashed wall at dusk, warm amber lamplight glowing through old uneven glass, thick painted wooden frame, four panes, the glass filling the centre of the frame, soft warm light spilling onto the pale wall around it, intimate and still,
```
*…+ shared tail.*

Upscale the best one. This is the anchor of the whole chain — spend generations here. Then
set it aside; §7 comes back to it.

### L8 · THE GLASS — `--zoom 2`

```text
the lit window of a small whitewashed cottage seen close, warm amber light in the glass, weathered wall around it, edge of an orange-red roof above, dusk,
```

### L7 · THE WINDOW — `--zoom 2`

```text
the front wall of a small isolated white cottage at dusk, one window lit warm amber, steep orange-red pitched roof above, plain wall, grass meeting the base of the wall,
```

### L6 · THE WALL — `--zoom 2`

```text
a single small isolated cottage with white walls and a steep orange-red pitched roof standing alone on green grass, one window glowing warm amber, no fence, no path, evening light,
```

### L5 · THE HOUSE — `--zoom 2`

```text
a single small isolated white cottage with orange-red roof standing alone on an open green hillside, one lit window, the cottage occupying about a third of the frame, long soft shadows across the grass,
```

### L4 · THE FIELD — `--zoom 2`

```text
a small white cottage with orange-red roof alone on a broad green hillside, seen from further back, the cottage small in the middle of the frame, wide bands of light and shadow crossing the grass, empty open ground all around it,
```

### L3 · THE SHOULDER — `--zoom 2`

```text
open rolling green hillside with one tiny white cottage far off in the middle distance, smooth folds of land, low brown-green ridge beginning to show at the right edge, deep cobalt sky filling the upper half,
```

### L2 · THE HILLSIDE — `--zoom 2`

```text
wide rolling green hills at dusk, a single tiny white cottage barely visible in the middle distance, long brown-green mountain ridge along the right side, low horizon in the lower third, vast empty cobalt sky above,
```

### L1 · THE FAR SLOPE — `--zoom 2`

```text
a wide green valley seen from a distance at dusk, layered hills receding, a long brown-green mountain ridge down the right side, the valley floor smooth and empty, a single point of warm light almost too small to see, low horizon, immense empty cobalt sky,
```

### L0 · THE VALLEY — `--zoom 2`

```text
an immense green valley seen from very high and far away at dusk, layered brown-green mountain ranges receding into pale blue distance, the whole valley floor visible and empty, one almost invisible speck of warm light somewhere near the centre, profound stillness and scale, low horizon in the lower third, vast deep cobalt sky filling the upper half,
```

---

## 5 · Check each step before continuing

A bad level poisons every level above it. Before you Zoom Out again, confirm:

- **The centre quarter still resembles the level below.** Zoom Out re-interprets the source
  rather than copying it pixel-for-pixel. Small drift is fine — the renderer feathers the seam.
  A cottage that changed roof colour is not fine.
- **Nothing was added at the ring boundary.** Midjourney will occasionally paint a horizon
  line, a wall, or a decorative edge exactly at the 25%/75% boundary. That is where the mask
  sits. Regenerate.
- **The horizon has not jumped.** Once it appears (around L3) it should sit in the lower third
  and stay there.
- **Sun still from the left.** Shadows fall right in every frame.
- **No new buildings.** The negative prompt catches most of it. Check anyway.

If a step drifts, regenerate *that step* from the level below. Never continue from a bad
frame — the error compounds nine times.

---

## 6 · Composition rules

These come from the renderer, not from taste:

- **The zoom target is always dead centre.** There is no version of this where the subject
  sits left of centre. The old "x = 0.35–0.5, wayfinder on the right" rule is void.
- **Keep 15–30% down and 78–88% down quiet.** Headline and counter live there.
- **Nothing high-contrast at the 25% / 75% boundary.**
- **Every level is seen twice** — once full frame, once as the centre quarter of its parent.
  It has to look deliberate at both. This is what will cost you the most regenerations.

---

## 7 · Closing the loop

This is the one image Midjourney cannot produce for you.

For the chain to be infinite, level 9's centre half must contain level 0. When the camera
reaches the window, what is on the other side of the glass is the whole valley, far away.

In an editor:

1. Take the final **L0** and scale it to exactly **50% linear**.
2. Place it dead centre of **L9** — occupying exactly the rect `(0.25, 0.25, 0.5, 0.5)`.
   Because both are `9:19`, L0 fits the window aperture exactly with no cropping.
3. Mask it to the glass. It should read as *seen through the pane*, not pasted on:
   - a soft amber multiply over it, matching the lamplight
   - a faint vertical reflection streak across the glass
   - very slight blur at the edges where the pane meets the frame
4. Keep the window's wooden frame and the wall **outside** the rect, untouched.

Then verify in the app: scrub depth from 9.0 to 10.0 and confirm it lands on 0.0 with no
visible discontinuity. That transition is either the best moment in the product or an obvious
bug, and there is not much in between. If it will not sell, set `ZoomChain.loops = false` and
ship the world going still at two months. That is an honest fallback, not a failure.

---

## 8 · Export

1. Upscale (Subtle), then Upscale 2×.
2. Downsample to exactly **1290 × 2796**. Never upscale anything smaller.
3. Export **HEIC**, quality 0.85. Roughly 1.2 MB each, ~12 MB for the chain — down from the
   25 MB of PNG currently in the bundle.
4. Keep the full-resolution masters outside the repo. If any single level has to be
   regenerated later, every level above it has to be regenerated too, and you will want the
   originals.

---

## 9 · Dropping them in

Create `ios/QuitNic/Assets.xcassets/ZoomL0.imageset/` … `ZoomL9.imageset/`, single-scale
`Contents.json` each. Then in `ZoomChain.levels`, swap each entry's `.procedural(seed:)` for
`.asset("ZoomL0")` and so on.

Nothing else changes. The renderer, the depth curve, Journey, Rescue and the light grade all
read from the same ten entries.
