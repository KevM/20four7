import SwiftUI

struct TagChipBar: View {
    let tags: [Tag]
    let selected: Set<String>
    let counts: [String: Int]
    let onToggle: (String) -> Void

    private var isPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: isPad ? 12 : 8) {
                chip(title: "All", count: nil, isOn: selected.isEmpty) { onToggle("__all__") }
                ForEach(tags) { tag in
                    chip(title: tag.name, count: counts[tag.id, default: 0], isOn: selected.contains(tag.id)) {
                        onToggle(tag.id)
                    }
                }
            }
            .padding(.horizontal, isPad ? 24 : 16)
        }
    }

    private func chip(title: String, count: Int?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: isPad ? 8 : 6) {
                Text(title)
                    .font(.system(size: isPad ? 19 : 15, weight: isOn ? .bold : .regular))
                
                if let count = count {
                    Text("\(count)")
                        .font(.system(size: isPad ? 14 : 11, weight: .bold))
                        .padding(.horizontal, isPad ? 7 : 5)
                        .padding(.vertical, isPad ? 2.5 : 1.5)
                        .background(isOn ? Color.black.opacity(0.12) : Color.white.opacity(0.15))
                        .foregroundStyle(isOn ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
                        .clipShape(Capsule())
                }
            }
            .padding(.vertical, isPad ? 10 : 6)
            .padding(.horizontal, isPad ? 16 : 12)
            .background(isOn ? Color.white : Color.white.opacity(0.12))
            .foregroundStyle(isOn ? Color.black : Color.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
