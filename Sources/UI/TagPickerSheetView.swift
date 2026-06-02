import SwiftUI

struct TagPickerSheetView: View {
    @ObservedObject var store: ChannelStore
    let isParentWide: Bool
    @Environment(\.dismiss) private var dismiss

    private var m: LayoutMetrics { LayoutMetrics(isParentWide ? .regular : .compact) }

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
                            TagChip(
                                title: tag.name,
                                count: store.tagChannelCounts[tag.id, default: 0],
                                isOn: store.selectedTagIDs.contains(tag.id),
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
            .background(Color.clear)
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
        .presentationBackground(.ultraThinMaterial)
    }
}
