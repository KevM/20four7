import SwiftUI

struct TagChipBar: View {
    let tags: [Tag]
    let selected: Set<String>
    let counts: [String: Int]
    let onToggle: (String) -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: m.chipRowSpacing) {
                chip(title: "All", count: nil, isOn: selected.isEmpty) { onToggle("__all__") }
                ForEach(tags) { tag in
                    chip(title: tag.name, count: counts[tag.id, default: 0], isOn: selected.contains(tag.id)) {
                        onToggle(tag.id)
                    }
                }
            }
            .padding(.horizontal, m.chipRowHPadding)
        }
    }

    private func chip(title: String, count: Int?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: m.chipInnerSpacing) {
                Text(title)
                    .font(m.chipFont.weight(isOn ? .bold : .regular))

                if let count = count {
                    Text("\(count)")
                        .font(m.chipCountFont)
                        .padding(.horizontal, m.chipCountHPadding)
                        .padding(.vertical, m.chipCountVPadding)
                        .background(isOn ? Color.black.opacity(0.12) : Color.white.opacity(0.15))
                        .foregroundStyle(isOn ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, m.chipVPadding)
            .padding(.horizontal, m.chipHPadding)
            .background(isOn ? Color.white : Color.white.opacity(0.12))
            .foregroundStyle(isOn ? Color.black : Color.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
