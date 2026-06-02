import SwiftUI

struct TagChipBar: View {
    let tags: [Tag]
    let selected: Set<String>
    let counts: [String: Int]
    let onToggle: (String) -> Void
    let onEditFilters: () -> Void

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: m.chipRowSpacing) {
                    // Only display selected chips horizontally
                    ForEach(tags.filter { selected.contains($0.id) }) { tag in
                        chip(title: tag.name, count: counts[tag.id, default: 0], isOn: true) {
                            onToggle(tag.id)
                        }
                    }
                }
                .padding(.leading, m.chipRowHPadding)
                .padding(.trailing, 24)
            }
            .mask(
                HStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        colors: [.black, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)
                }
            )

            // Filter Trigger Button pinned to the far right
            Button(action: onEditFilters) {
                HStack(spacing: m.chipInnerSpacing) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.subheadline)
                    if selected.isEmpty {
                        Text("Filter")
                            .font(m.chipFont.weight(.semibold))
                    } else if m.wide {
                        Text("Edit Filters")
                            .font(m.chipFont.weight(.semibold))
                    }
                    if !selected.isEmpty {
                        Text("\(selected.count)")
                            .font(m.chipCountFont)
                            .padding(.horizontal, m.chipCountHPadding)
                            .padding(.vertical, m.chipCountVPadding)
                            .background(Color.white.opacity(0.2))
                            .foregroundStyle(Color.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.vertical, m.chipVPadding)
                .padding(.horizontal, m.chipHPadding)
                .background(selected.isEmpty ? Color.white.opacity(0.12) : Color.blue)
                .foregroundStyle(.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.trailing, m.chipRowHPadding)
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
