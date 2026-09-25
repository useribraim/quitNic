# Horizon opacity audit

Audited 8 August 2026 against all six delivery JPEGs at their native aspect
ratios. This is an asset-level review; rendered light/dark snapshots remain a
separate release check.

The plates already contain deep black valleys, heavy green shadows, and strong
cobalt skies. The previous maximum multiply grade of `0.78`, combined with a
`0.38` vignette and `0.50` lower-screen shade, crushed terrain detail at night.
The night grade now tops out at `0.56`; the vignette and tab-area shade are
reduced to `0.26` and `0.42`. Midday remains ungraded so the original palette is
not washed out.

Functional surfaces do not depend on the art grade for contrast: Today’s support
dock, cards, and tab surface use opaque semantic design tokens. Text opacities
remain hierarchy tokens and are not tuned per plate.

Still required before submission: capture each plate through the real renderer at
midday and starlight, then compare those twelve references for clipping, contrast,
and unintended colour casts.
