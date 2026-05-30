import SwiftUI

struct TagChipBar: View {
    let tags: [Tag]
    let selected: Set<String>
    let onToggle: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(title: "All", isOn: selected.isEmpty) { onToggle("__all__") }
                ForEach(tags) { tag in
                    chip(title: tag.name, isOn: selected.contains(tag.id)) { onToggle(tag.id) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(isOn ? .bold : .regular))
                .padding(.vertical, 6).padding(.horizontal, 12)
                .background(isOn ? Color.white : Color.white.opacity(0.12))
                .foregroundStyle(isOn ? Color.black : Color.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
