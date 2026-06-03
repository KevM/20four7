import SwiftUI

/// Shared "Tags" + "Add Custom Tag" form sections used by the add and edit
/// channel forms. Selection is driven through `selectedTagIDs`; creating a custom
/// tag inserts its trimmed name into the selection.
struct TagSelectorSection: View {
    let availableTags: [Tag]
    @Binding var selectedTagIDs: Set<String>

    @State private var newTagName = ""

    var body: some View {
        Group {
            Section("Tags") {
                FlowLayout(spacing: 8) {
                    ForEach(availableTags) { tag in
                        let isSelected = selectedTagIDs.contains(tag.id)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                                if isSelected { selectedTagIDs.remove(tag.id) }
                                else { selectedTagIDs.insert(tag.id) }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption2)
                                }
                                Text(tag.name)
                                    .font(.caption)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(isSelected ? Color.blue : Color(.systemGray6))
                            .foregroundColor(isSelected ? .white : .primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Add Custom Tag") {
                HStack {
                    TextField("New tag name (e.g. Nature)", text: $newTagName)
                        .autocorrectionDisabled()
                    Button("Create") {
                        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            selectedTagIDs.insert(trimmed)
                            newTagName = ""
                        }
                    }
                    .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
