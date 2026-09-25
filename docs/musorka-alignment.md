# `musorka` design alignment

Reviewed against every image in `/musorka` on 8 August 2026.

## Current fit

The app is now roughly **8.5/10 aligned** with the reference direction. It uses the
same strongest ingredients: saturated cobalt, deep green, vermillion accents, warm
ivory, sparse editorial headlines, grainy landscape art, and asymmetrical negative
space. Before this pass, the artwork was aligned but the interface around it was still
a conventional stack of grey/translucent rounded cards.

The strongest matches are Today's full-bleed landscape, Rescue's quiet focal point,
Journey's ivory feature panel and forest roadmap, and the new Coach/Quick Log opening
composition. Native Settings keeps familiar Form behaviour for scanning, permissions,
and destructive controls, but its palette and type preview now belong to Horizon.
The app icon now uses the same cobalt sky, rising forest hill, ivory house, vermilion
roof, and restrained print grain; the legacy teal wellness-leaf icon is archived under
`musorka/source-plates` rather than shipping as a second brand.

## Canonical rules

1. Compose from cobalt, deep cobalt, paper, paper ink, forest, plum, and vermillion.
2. Vermillion means current action, urgency, or current waypoint; it is not decoration.
3. Use artwork or negative space as the large surface. Do not fill every gap with a card.
4. Use opaque reading surfaces over detailed artwork; translucent material is not a text background.
5. Use a tracked uppercase eyebrow, one large editorial headline, then plain readable body copy.
6. Keep functional controls familiar. The visual identity comes from composition, colour, type, and art.
7. Keep radii tight and intentional: 12–14 points for product panels; circles only for icon controls.
8. Font style is a reader choice—Soft, Modern, or Editorial—not a custom text-size control.

## Approved shipping plates and crop rules

All shipping images are opaque JPEGs in `Assets.xcassets`; higher-resolution working
sources stay under `musorka/source-plates`. Product screens use `scaledToFill` and may
crop edges, but must never move the focal subject beneath controls.

| Asset | Purpose | Protected focal area |
| --- | --- | --- |
| `HorizonOverlook` | First wide sense of distance | Small house in the lower centre; keep the upper sky clear for Today’s headline |
| `HorizonHouse` | Closer human-scale checkpoint | House around the lower-middle third; do not place actions over its roof or doorway |
| `HorizonRidge` | Abstract forward movement | Crossing ridge lines in the lower half; preserve the open blue upper half for copy |
| `HorizonValley` | Deepest, calmest landscape | Orange saddle and water reflection through the centre; reading copy needs an opaque surface |
| `HorizonNewHorizon` | Long-horizon arrival | Orange horizon and sun around mid-height; never crop both out simultaneously |
| `HorizonLand` | Journey hero only | Tiny house left of centre and mountain ridge at upper right; crop outer sides first |

Time-of-day grading, vignette, and device-safe crops are renderer concerns; source files
must remain ungraded. The artwork’s red is reserved for action, urgency, or the current
waypoint, not generic reward decoration.

## Remaining gaps

- Physical-device light/dark crop snapshots still need to cover every plate.
- Craving state orchestration remains sizeable, though form controls, history editing,
  voice input, and the Rescue breathing presentation now live in focused components.
- A five-person adjective test should confirm the experience reads as vivid, calm, hopeful, clear, and trustworthy.
- Clinical approval metadata is still required before medical milestone wording can ship.

The full implementation and gate ledger is in `product-improvement-audit.md`.
