import SwiftUI

/// Horizontal display of the currently-active filter chips. Tapping a chip removes
/// that filter. The Filter entry point lives in the toolbar (see RootView), so this
/// bar is only shown when at least one tag is selected.
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
                ForEach(tags.filter { selected.contains($0.id) }) { tag in
                    TagChip(
                        title: tag.name,
                        count: counts[tag.id, default: 0],
                        isOn: true,
                        m: m,
                        action: { onToggle(tag.id) }
                    )
                }
            }
            .padding(.leading, m.chipRowHPadding)
            .padding(.trailing, 24)
        }
        .mask(
            // Fade the right edge so overflowing chips trail off rather than clip hard.
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
    }
}
