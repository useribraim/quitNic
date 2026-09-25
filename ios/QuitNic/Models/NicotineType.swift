import Foundation

/// The kind of nicotine product someone is quitting. Backed by a plain string on
/// `QuitPlan` (and the backend's `Literal` field) for storage simplicity; this type
/// centralizes what used to be duplicated raw-string switches across Onboarding,
/// Settings, and the plan editor, so every screen agrees on the noun and label for a
/// given type instead of drifting independently.
enum NicotineType: CaseIterable, Identifiable, Equatable {
    case pouches, cigarettes, vape, other

    var id: String { storedValue }

    init(storedValue: String) {
        switch storedValue {
        case "pouches": self = .pouches
        case "vape": self = .vape
        case "other": self = .other
        default: self = .cigarettes
        }
    }

    var storedValue: String {
        switch self {
        case .pouches: "pouches"
        case .cigarettes: "cigarettes"
        case .vape: "vape"
        case .other: "other"
        }
    }

    var displayName: String {
        switch self {
        case .pouches: "Nicotine Pouches"
        case .cigarettes: "Cigarettes"
        case .vape: "Vape"
        case .other: "Other"
        }
    }

    /// Plural noun for "X per day", stepper labels, and similar.
    var unitNounPlural: String {
        switch self {
        case .pouches: "pouches"
        case .cigarettes: "cigarettes"
        case .vape: "vape sessions"
        case .other: "units"
        }
    }

    /// Singular noun for "Cost per pouch" style labels.
    var unitNounSingular: String {
        switch self {
        case .pouches: "pouch"
        case .cigarettes: "cigarette"
        case .vape: "vape session"
        case .other: "unit"
        }
    }

    /// Pouches are sold by the can, so most people know a per-can price, not a per-pouch
    /// one — asking directly for "cost per pouch" produces a guess, not a real number.
    var supportsPerContainerPricing: Bool { self == .pouches }
}
