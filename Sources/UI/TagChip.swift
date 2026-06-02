import SwiftUI

struct TagChip: View {
    let title: String
    let count: Int?
    let isOn: Bool
    let m: LayoutMetrics
    let action: () -> Void

    var body: some View {
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
