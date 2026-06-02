import SwiftUI

struct TagChipBar: View {
    let tags: [Tag]
    let selected: Set<String>
    let counts: [String: Int]
    let onToggle: (String) -> Void

    @State private var isExpanded = false

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Filter by Tags")
                            .font(.subheadline.bold())
                            .foregroundColor(.white.opacity(0.9))
                        Spacer()
                        expandCollapseButton
                    }
                    .padding(.horizontal, m.chipRowHPadding)

                    FlowLayout(spacing: m.chipRowSpacing) {
                        chip(title: "All", count: nil, isOn: selected.isEmpty) { onToggle("__all__") }
                        ForEach(tags) { tag in
                            chip(title: tag.name, count: counts[tag.id, default: 0], isOn: selected.contains(tag.id)) {
                                onToggle(tag.id)
                            }
                        }
                    }
                    .padding(.horizontal, m.chipRowHPadding)
                }
                .padding(.vertical, 12)
                .background(Color.white.opacity(0.04))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .padding(.horizontal, 12)
            } else {
                HStack(spacing: 0) {
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
                    
                    expandCollapseButton
                        .padding(.trailing, m.chipRowHPadding)
                }
            }
        }
    }

    private var expandCollapseButton: some View {
        Button(action: {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                isExpanded.toggle()
            }
        }) {
            Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                .font(.title2)
                .foregroundColor(.white.opacity(0.7))
                .padding(.leading, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
