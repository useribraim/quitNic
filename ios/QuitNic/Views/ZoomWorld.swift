import SwiftUI

// MARK: - The chain

/// One frame of the zoom chain: a plate, and where it sits in the order.
///
/// This used to also carry a `nextFrame` unit rect and a derived `stepScale`, for a
/// nesting composite that no longer exists (see the note on `ZoomChain`), plus a
/// display `name` nothing ever showed. The renderer needs the image and the index.
struct ZoomLevel: Identifiable, Equatable {
    let id: Int
    let assetName: String
}

/// One world, walked at a speed set by time alone.
///
/// The spec asks for ten outpainted frames that nest exactly, so the camera can fall
/// forever into a lit window. That chain does not exist yet, and until it does the
/// choice is between a hand-drawn approximation of the art and the art. This is the
/// art: five finished plates, in the order they were composed, each one pushed in
/// continuously and dissolved into the next.
///
/// The cost is honest and worth naming — separately composed images cannot nest, so
/// there is no true infinite zoom here, only a continuous walk through five real
/// places. `horizon-zoom.md` calls the dissolve the honest fallback, and a beautiful
/// fallback beats an accurate placeholder nobody wants to look at. When the outpainted
/// chain is generated, this list grows and nothing else has to move.
enum ZoomChain {
    /// false → depth clamps at `count - 1` and the world goes still past two months.
    static let loops = true

    static let levels: [ZoomLevel] = [
        "HorizonOverlook",
        "HorizonHouse",
        "HorizonRidge",
        "HorizonValley",
        "HorizonNewHorizon"
    ].enumerated().map { ZoomLevel(id: $0.offset, assetName: $0.element) }

    static var count: Int { levels.count }

    /// Unbounded. Depth is not clamped — the chain wraps: level 9's `nextFrame`
    /// contains a miniature of level 0, so `level(10)` is `level(0)`.
    static func level(_ index: Int) -> ZoomLevel {
        levels[((index % count) + count) % count]
    }

    /// What the camera is allowed to show for a given raw depth, honouring the
    /// loop switch. With the loop off the world goes still at the last level.
    static func displayDepth(_ depth: Double) -> Double {
        loops ? depth : min(max(depth, 0), Double(count - 1))
    }

}

// MARK: - Depth from time

/// Time is the only engine: hours nicotine-free map to camera depth. Milestones are
/// logarithmic — 2h, 8h, 48h … 1440h — so depth is logarithmic too; linear time would
/// make day one invisible and month two a blur.
enum ZoomDepth {
    /// The first milestone, in hours. Sets where the curve starts biting.
    static let h0: Double = 2

    /// The last milestone, in hours — two months. One complete traversal of the world
    /// is worth exactly this much nicotine-free time.
    static let traversalHours: Double = 1_440

    /// Fitted so the final milestone lands exactly on one complete traversal. Derived
    /// from the length of the chain rather than written down, so adding plates
    /// lengthens the journey instead of silently changing where two months lands.
    static var k: Double {
        Double(ZoomChain.count) / log2(1 + traversalHours / h0)
    }

    static func depth(hoursFree: Double) -> Double {
        guard hoursFree > 0 else { return 0 }
        return k * log2(1 + hoursFree / h0)
    }

    static func depth(streakStart: Date, now: Date = .now) -> Double {
        depth(hoursFree: max(0, now.timeIntervalSince(streakStart)) / 3_600)
    }

    /// Inverse of `depth(hoursFree:)` — how many nicotine-free hours a depth stands
    /// for. Lets the Journey scrub say when a scrubbed-to point was, or will be, real.
    static func hours(atDepth depth: Double) -> Double {
        guard depth > 0 else { return 0 }
        return h0 * (pow(2, depth / k) - 1)
    }
}

// MARK: - The light axis

struct ColorGrade: Equatable {
    let tint: Color
    let opacity: Double
    let blendMode: BlendMode
}

/// Local time of day, graded over the whole composited world. Orthogonal to depth on
/// purpose: someone at depth 8 at noon and someone at depth 2 at noon are standing in
/// the same daylight, at different distances. The payoff is that 3am looks like 3am.
enum HorizonLight {
    /// One keyframe of the day. The colours are the 17 hand-tuned land tints from the
    /// location era, retained exactly; only what indexes them changed — hour of day
    /// instead of place. Interpolated, not selected: light is continuous like depth is.
    private struct Key {
        let hour: Double
        let red: Double
        let green: Double
        let blue: Double
        let opacity: Double
        /// .multiply for night, .overlay for warm hours.
        let blend: BlendMode
    }

    /// Starlight appears twice so the small hours hold steady dark instead of
    /// interpolating toward dawn all night — 3am must not look half-lit.
    private static let keys: [Key] = [
        Key(hour: 4.25, red: 20, green: 20, blue: 42, opacity: 0.56, blend: .multiply),   // STARLIGHT
        Key(hour: 5.0, red: 70, green: 60, blue: 110, opacity: 0.45, blend: .multiply),   // FIRST LIGHT
        Key(hour: 6.0, red: 80, green: 74, blue: 118, opacity: 0.34, blend: .multiply),   // SUNRISE
        Key(hour: 7.0, red: 74, green: 92, blue: 120, opacity: 0.25, blend: .multiply),   // EARLY
        Key(hour: 8.0, red: 60, green: 110, blue: 150, opacity: 0.14, blend: .multiply),  // MORNING
        Key(hour: 9.5, red: 96, green: 162, blue: 226, opacity: 0, blend: .overlay),      // FORENOON
        Key(hour: 11.0, red: 96, green: 162, blue: 226, opacity: 0, blend: .overlay),     // MIDDAY
        Key(hour: 13.0, red: 82, green: 150, blue: 220, opacity: 0, blend: .overlay),     // HIGH SUN
        Key(hour: 15.0, red: 104, green: 158, blue: 214, opacity: 0, blend: .overlay),    // AFTERNOON
        Key(hour: 16.5, red: 120, green: 120, blue: 90, opacity: 0.12, blend: .overlay),  // LATE DAY
        Key(hour: 18.0, red: 150, green: 110, blue: 80, opacity: 0.20, blend: .overlay),  // GOLDEN
        Key(hour: 19.0, red: 168, green: 96, blue: 70, opacity: 0.30, blend: .overlay),   // SUNSET
        Key(hour: 19.75, red: 150, green: 74, blue: 66, opacity: 0.40, blend: .overlay),  // AFTERGLOW
        Key(hour: 20.5, red: 108, green: 56, blue: 66, opacity: 0.42, blend: .multiply),  // DUSK
        Key(hour: 21.25, red: 70, green: 42, blue: 62, opacity: 0.48, blend: .multiply),  // LAST LIGHT
        Key(hour: 22.0, red: 44, green: 32, blue: 56, opacity: 0.52, blend: .multiply),   // TWILIGHT
        Key(hour: 23.0, red: 28, green: 24, blue: 48, opacity: 0.55, blend: .multiply),   // NIGHTFALL
        Key(hour: 23.75, red: 20, green: 20, blue: 42, opacity: 0.56, blend: .multiply)   // STARLIGHT
    ]

    static func grade(at date: Date, calendar: Calendar = .current) -> ColorGrade {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return grade(atHour: Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60)
    }

    /// Interpolated on demand. A precomputed 1,440-entry minute table used to stand here
    /// to avoid allocating a colour per frame; measured, one interpolation costs 0.24 µs
    /// — 14 µs per second at 60 fps — while the table cost 373 µs to build and held
    /// 144 kB of SwiftUI colours for the life of the process.
    static func grade(atHour hour: Double) -> ColorGrade {
        let t = hour.truncatingRemainder(dividingBy: 24)
        // Wrap segment: last key of one day to first key of the next. Both ends are
        // starlight, so the whole stretch 23.75 → 4.25 is constant deep night.
        var lower = keys[keys.count - 1]
        var upper = keys[0]
        var span = (24 - lower.hour) + upper.hour
        var offset = t < upper.hour ? t + (24 - lower.hour) : t - lower.hour
        for index in 0..<(keys.count - 1) where t >= keys[index].hour && t < keys[index + 1].hour {
            lower = keys[index]
            upper = keys[index + 1]
            span = upper.hour - lower.hour
            offset = t - lower.hour
        }
        let fraction = span > 0 ? min(1, max(0, offset / span)) : 0
        // Blend modes cannot interpolate; the keyframe carrying more of the look wins
        // the segment. Both grades drift over hours, so the handover is never abrupt
        // at any opacity that would make it visible.
        let dominant = lower.opacity >= upper.opacity ? lower : upper
        return ColorGrade(
            tint: Color(
                red: (lower.red + (upper.red - lower.red) * fraction) / 255,
                green: (lower.green + (upper.green - lower.green) * fraction) / 255,
                blue: (lower.blue + (upper.blue - lower.blue) * fraction) / 255
            ),
            opacity: lower.opacity + (upper.opacity - lower.opacity) * fraction,
            blendMode: dominant.blend
        )
    }
}


// MARK: - The renderer

/// Two images on screen, ever: the plate the camera is in, pushing slowly forward, and
/// the next one dissolving in underneath it as the depth crosses over.
///
/// The nesting composite this replaced was built for an outpainted chain where level
/// `n + 1` is literally the middle of level `n`. Five separately composed paintings are
/// not that, and drawing them as if they were put the second one at half scale in the
/// centre of the first — a picture inside a picture. Between distinct compositions the
/// dissolve is the truthful move.
struct ZoomWorldView: View, Animatable {
    var depth: Double
    /// The clock the light grade is read from. Deliberately not defaulted to `.now`:
    /// a default evaluated at each construction gave the view a new value on every body
    /// evaluation, so it could never compare equal to its predecessor. Callers pass the
    /// same `now` they already hold, and Rescue — which has no clock of its own on
    /// screen — pins one for the length of the sequence.
    var date: Date
    /// Rescue's breathing rides the light axis: warmth rises on the inhale, cools on
    /// the exhale. 0 everywhere else.
    var warmth: Double = 0

    /// Animating depth itself — rather than the derived scale factors — is what lets
    /// a spring cross level boundaries without the images swapping mid-flight.
    var animatableData: Double {
        get { depth }
        set { depth = newValue }
    }

    var body: some View {
        GeometryReader { geo in
            let d = ZoomChain.displayDepth(depth)
            let n = Int(floor(d))
            let f = d - Double(n)
            let current = ZoomChain.level(n)
            let next = ZoomChain.level(n + 1)
            let grade = HorizonLight.grade(at: date)
            // A slow push across the whole plate rather than a doubling. Anything more
            // and the last stretch of every level is a soft, over-magnified crop.
            let push = 1 + 0.42 * f
            // The handover happens late and quickly, so most of the time you are simply
            // somewhere, moving — not watching two pictures argue.
            let blend = Self.smoothstep(f, from: 0.74, to: 1)

            ZStack {
                ZStack {
                    levelContent(current, size: geo.size)
                        .scaleEffect(push)

                    // The incoming plate arrives at rest, unmagnified, so arriving
                    // somewhere new feels like the camera settling rather than another
                    // lurch forward.
                    // Create the incoming image shortly before the dissolve, not on every
                    // screen from launch. On the early part of a level it is fully hidden;
                    // eagerly instantiating it still decoded another 3–6 MB source plate.
                    if f >= 0.74 {
                        levelContent(next, size: geo.size)
                            .opacity(blend)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .clipped()

                Rectangle()
                    .fill(grade.tint)
                    .opacity(grade.opacity)
                    .blendMode(grade.blendMode)

                Rectangle()
                    .fill(HorizonTheme.breathingWarmth)
                    .opacity(warmth * 0.20)
                    .blendMode(.overlay)

                // The tab bar carries no fill, so the ground has to hold it.
                LinearGradient(
                    colors: [.clear, .black.opacity(0.42)],
                    startPoint: UnitPoint(x: 0.5, y: 0.76),
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Eased 0…1, so the dissolve has no corner at either end.
    static func smoothstep(_ x: Double, from: Double, to: Double) -> Double {
        guard to > from else { return x >= to ? 1 : 0 }
        let t = min(1, max(0, (x - from) / (to - from)))
        return t * t * (3 - 2 * t)
    }

    private func levelContent(_ level: ZoomLevel, size: CGSize) -> some View {
        Image(level.assetName)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
    }
}

// MARK: - Standing in the world

/// How much the world is dimmed for the screen standing in it.
///
/// The three tabs used to paint three unrelated backgrounds: Today drew the landscape,
/// while Journey and Coach each drew a flat cobalt gradient. Moving between them read as
/// moving between three apps. There is one world now, drawn once behind the tab bar, and
/// a screen only says how much light it needs to be readable.
enum HorizonScrim: Equatable {
    /// Today: a headline and one line of caption. The landscape carries the screen.
    case none
    /// Journey and Coach: long-form reading. The same view, seen through glass.
    case reading

    var glassOpacity: Double {
        switch self {
        case .none: 0
        case .reading: 1
        }
    }
}

/// Where the camera stands, shared by every screen in the tab container.
///
/// A `TabView` page paints its own opaque background, so the world cannot simply sit
/// behind the tabs — each screen has to draw it. Passing it down the environment is what
/// keeps the three drawings identical: one depth, one clock, set in one place.
struct HorizonWorld: Equatable {
    var depth: Double
    var date: Date
}

private struct HorizonWorldKey: EnvironmentKey {
    static let defaultValue = HorizonWorld(depth: 0, date: .now)
}

extension EnvironmentValues {
    var horizonWorld: HorizonWorld {
        get { self[HorizonWorldKey.self] }
        set { self[HorizonWorldKey.self] = newValue }
    }
}

/// The world, plus the glass a reading screen looks at it through.
///
/// The glass is a real material rather than a flat colour wash, so the landscape's shape
/// and the time of day still come through behind the text — the tab change reads as the
/// lights coming down in the same room, not as a different room.
struct HorizonWorldBackdrop: View {
    @Environment(\.horizonWorld) private var world
    var scrim: HorizonScrim

    var body: some View {
        ZoomWorldView(depth: world.depth, date: world.date)
            .overlay {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                    .overlay(
                        LinearGradient(
                            colors: [
                                HorizonTheme.deepCobalt.opacity(0.30),
                                HorizonTheme.deepCobalt.opacity(0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(scrim.glassOpacity)
            }
            .ignoresSafeArea()
    }
}

extension View {
    /// Puts this screen inside the shared world rather than on its own background.
    func insideHorizonWorld(_ scrim: HorizonScrim) -> some View {
        background(HorizonWorldBackdrop(scrim: scrim))
    }
}
