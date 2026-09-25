# Horizon asset performance baseline

Measured 9 August 2026 from the delivery catalogue and an iPhone 16 Pro Simulator
running iOS 18.0. This is a repeatable regression baseline, not a physical-device
Release-memory claim.

| Delivery plate | Pixels | Encoded | Approximate RGBA decode |
| --- | ---: | ---: | ---: |
| `HorizonHouse` | 1203 × 2622 | 0.81 MB | 12.03 MiB |
| `HorizonLand` | 1946 × 808 | 0.65 MB | 6.00 MiB |
| `HorizonNewHorizon` | 945 × 2048 | 0.59 MB | 7.38 MiB |
| `HorizonOverlook` | 945 × 2048 | 0.73 MB | 7.38 MiB |
| `HorizonRidge` | 1203 × 2622 | 0.79 MB | 12.03 MiB |
| `HorizonValley` | 1203 × 2622 | 0.64 MB | 12.03 MiB |

The six JPEGs total 4.20 MB encoded. House, Ridge, and Valley were cropped to the
shipped viewport aspect ratio, bounded to the iPhone 16 Pro's 1206 × 2622 viewport,
and JPEG-encoded at quality 82. SSIM against the equivalently cropped originals was
0.955, 0.942, and 0.962. Quality 90 improved SSIM by only about 0.004 while producing
files about 25% larger. Full-resolution delivery sources remain in
`musorka/source-plates`; they are not in the app catalogue.

The XCTest physical-memory metric averaged 43,081 kB with a 54,844 kB average peak.
Before bounding the three oversized plates, the same test averaged 45,063 kB physical
and 59,219 kB peak: reductions of 4.4% and 7.4%. Debug simulator measurements include
SwiftUI, diagnostics, and simulator overhead, so compare only like-for-like runs.

`ZoomWorldView` instantiates the current plate and creates the incoming plate only
after depth fraction 0.74. The largest expected two-plate source decode is therefore
approximately 24.07 MiB before GPU textures and framework overhead. Because the
shipped sources are already viewport-bounded, a custom ImageIO thumbnail loader would
add code and cache complexity without reducing the source bound further.

All five zoom-chain plates are reachable from Today because the chain loops. Splitting
nominal Journey/Rescue plates into on-demand tags would therefore create a false launch
boundary. `HorizonLand` is separately visible during onboarding. Physical-device
Release profiling remains part of the TestFlight gate.

Reproduce the static footprint with `sips -g pixelWidth -g pixelHeight` and `stat`.
Reproduce memory with the `testPerformanceTodayMemory` UI test and compare the XCTest
physical-memory and peak samples, not process RSS.
