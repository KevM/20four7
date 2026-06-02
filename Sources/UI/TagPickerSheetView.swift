import SwiftUI

struct TagPickerSheetView: View {
    @ObservedObject var store: ChannelStore
    @Environment(\.dismiss) private var dismiss

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Select one or more tags to filter the guide lineup.")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .padding(.horizontal, 16)

                    FlowLayout(spacing: m.chipRowSpacing) {
                        ForEach(store.chipTags) { tag in
                            TagPickerChipView(
                                tag: tag,
                                isSelected: store.selectedTagIDs.contains(tag.id),
                                count: store.tagChannelCounts[tag.id, default: 0],
                                m: m,
                                action: {
                                    withAnimation {
                                        store.toggleTag(tag.id)
                                    }
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 12)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if !store.selectedTagIDs.isEmpty {
                        Button("Clear All") {
                            withAnimation {
                                store.selectedTagIDs.removeAll()
                            }
                        }
                        .foregroundColor(.red)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .bold()
                    .foregroundColor(.white)
                }
            }
        }
    }
}

struct TagPickerChipView: View {
    let tag: Tag
    let isSelected: Bool
    let count: Int
    let m: LayoutMetrics
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: m.chipInnerSpacing) {
                Text(tag.name)
                    .font(m.chipFont.weight(isSelected ? .bold : .regular))

                Text("\(count)")
                    .font(m.chipCountFont)
                    .padding(.horizontal, m.chipCountHPadding)
                    .padding(.vertical, m.chipCountVPadding)
                    .background(isSelected ? Color.black.opacity(0.12) : Color.white.opacity(0.15))
                    .foregroundStyle(isSelected ? Color.black.opacity(0.7) : Color.white.opacity(0.7))
                    .clipShape(Capsule())
            }
            .padding(.vertical, m.chipVPadding)
            .padding(.horizontal, m.chipHPadding)
            .background(isSelected ? Color.white : Color.white.opacity(0.12))
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
