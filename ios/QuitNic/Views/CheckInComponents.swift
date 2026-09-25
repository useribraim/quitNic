import SwiftUI

struct OutcomeChoice: View {
    let title: String
    let detail: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HorizonLayout.control) {
                Text(title)
                    .font(HorizonType.body(.subheadline).weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? HorizonTheme.accentText : HorizonTheme.secondaryText)
            }
            .padding(.horizontal, HorizonLayout.control)
            .padding(.vertical, HorizonLayout.compact)
            .background(isSelected ? HorizonTheme.accent.opacity(0.18) : HorizonTheme.surface, in: RoundedRectangle(cornerRadius: HorizonLayout.panelRadius))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(detail)")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }
}

struct IntensityControl: View {
    let title: String
    @Binding var value: Double

    private var descriptor: String {
        switch Int(value) {
        case 1...3: "Mild"
        case 4...6: "Moderate"
        case 7...8: "Strong"
        default: "Very strong"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HorizonLayout.content) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: HorizonLayout.micro) {
                    Text(title).font(HorizonType.body(.headline))
                    Text(descriptor)
                        .font(HorizonType.body(.caption).weight(.semibold))
                        .foregroundStyle(HorizonTheme.secondaryText)
                }
                Spacer()
                Text("\(Int(value))")
                    .font(HorizonType.body(.largeTitle).weight(.bold))
                    .foregroundStyle(HorizonTheme.accentText)
            }
            Slider(value: $value, in: 1...10, step: 1)
                .tint(HorizonTheme.accent)
                .accessibilityLabel(title)
                .accessibilityValue("\(Int(value)) out of 10, \(descriptor)")
            HStack {
                Text("1").accessibilityHidden(true)
                Spacer()
                Text("10").accessibilityHidden(true)
            }
            .font(HorizonType.body(.caption))
            .foregroundStyle(HorizonTheme.secondaryText)
        }
    }
}

struct TriggerChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: HorizonLayout.compact) {
                if isSelected { Image(systemName: "checkmark") }
                Text(title)
            }
            .font(HorizonType.body(.subheadline).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, HorizonLayout.content)
            .padding(.vertical, HorizonLayout.control)
            .background(
                isSelected ? HorizonTheme.accent : HorizonTheme.surface,
                in: Capsule()
            )
            .overlay { Capsule().strokeBorder(isSelected ? Color.clear : HorizonTheme.border, lineWidth: HorizonLayout.hairline) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct OutcomeMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: HorizonLayout.tight) {
            Text(value)
                .font(HorizonType.body(.largeTitle).weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(HorizonType.body(.caption).weight(.semibold))
                .foregroundStyle(HorizonTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .horizonCard()
    }
}

struct FlowLayout: Layout {
    let spacing: CGFloat

    /// SwiftUI always calls `sizeThatFits` and then `placeSubviews` with the same
    /// proposal. Without a cache this measured every chip twice per pass — the trigger
    /// picker re-measured seven of them on each keystroke in the custom-trigger field.
    struct Cache {
        var width: CGFloat
        var result: (size: CGSize, points: [CGPoint])
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(width: .nan, result: (.zero, []))
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        cache.width = .nan
    }

    private func resolved(_ cache: inout Cache, proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 0
        if cache.width == width { return cache.result }
        let result = layout(proposal: proposal, subviews: subviews)
        cache.width = width
        cache.result = result
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        resolved(&cache, proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = resolved(&cache, proposal: proposal, subviews: subviews)
        for (index, point) in result.points.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, points: [CGPoint]) {
        let width = proposal.width ?? 0
        var points: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            points.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), points)
    }
}
