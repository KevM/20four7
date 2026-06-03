import SwiftUI

struct ChannelTile: View {
    let channel: Channel
    let isFavorite: Bool
    let isOffline: Bool
    let onTap: () -> Void
    var onToggleFavorite: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    @State private var showRemoveConfirmation = false

    var body: some View {
        Button(action: onTap) {
            ChannelTileContent(
                channel: channel,
                isFavorite: isFavorite,
                isOffline: isOffline,
                height: m.tileHeight,
                isPreview: false,
                m: m
            )
        }
        .buttonStyle(.plain)
        .confirmationDialog("Remove \(channel.title)?", isPresented: $showRemoveConfirmation, titleVisibility: .visible) {
            if let onRemove {
                Button("Remove", role: .destructive, action: onRemove)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This channel will be removed from your guide.")
        }
        .contextMenu {
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
                }
            }
            if let onEdit {
                Button {
                    onEdit()
                } label: {
                    Label("Edit…", systemImage: "pencil")
                }
            }
            if onRemove != nil {
                Divider()
                Button(role: .destructive) {
                    showRemoveConfirmation = true
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        } preview: {
            ChannelTileContent(
                channel: channel,
                isFavorite: isFavorite,
                isOffline: isOffline,
                height: m.contextMenuPreviewHeight,
                isPreview: true,
                m: m
            )
            .frame(width: m.contextMenuPreviewWidth, height: m.contextMenuPreviewHeight)
        }
    }
}

struct ChannelTileContent: View {
    let channel: Channel
    let isFavorite: Bool
    let isOffline: Bool
    let height: CGFloat
    let isPreview: Bool
    let m: LayoutMetrics

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            CachedThumbnail(url: channel.resolvedThumbnailURL, targetHeight: height)
                .frame(maxWidth: .infinity, maxHeight: height)
                .clipped()

            LinearGradient(colors: [.clear, .black.opacity(0.8)],
                           startPoint: .center, endPoint: .bottom)

            HStack(alignment: .bottom) {
                Text(channel.title)
                    .font(isPreview ? m.contextMenuPreviewTitleFont : m.tileTitleFont)
                    .lineLimit(isPreview ? 2 : 1)
                    .multilineTextAlignment(.leading)
                Spacer()
                if isOffline {
                    Text("OFFLINE")
                        .font(isPreview ? m.contextMenuPreviewOfflineFont : m.tileOfflineFont)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, isPreview ? m.contextMenuPreviewOfflineHPadding : m.tileOfflineHPadding)
                        .padding(.vertical, isPreview ? m.contextMenuPreviewOfflineVPadding : m.tileOfflineVPadding)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            .padding(isPreview ? (m.wide ? 18 : 12) : m.tilePadding)

            if isFavorite {
                Image(systemName: "star.fill")
                    .font(isPreview ? (m.wide ? .title : .title2) : m.tileFavoriteFont)
                    .foregroundStyle(.yellow)
                    .padding(isPreview ? (m.wide ? 18 : 12) : m.tilePadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        // Fixed height (not maxHeight) so the placeholder reserves the tile's final
        // size; otherwise the tile sizes to the text until the thumbnail loads and
        // then reflows when the image grows it to full height.
        .frame(maxWidth: .infinity, minHeight: height, maxHeight: height)
        .clipShape(RoundedRectangle(cornerRadius: m.tileCornerRadius))
        .foregroundStyle(.white)
        .opacity(isOffline ? 0.6 : 1.0)
        .grayscale(isOffline ? 1.0 : 0.0)
    }
}
