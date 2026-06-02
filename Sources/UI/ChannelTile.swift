import SwiftUI

struct ChannelTile: View {
    let channel: Channel
    let isFavorite: Bool
    let isOffline: Bool
    let onTap: () -> Void
    var onToggleFavorite: (() -> Void)? = nil
    var onRename: (() -> Void)? = nil
    var onToggleLive: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: channel.resolvedThumbnailURL) { image in
                    image.resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity, maxHeight: m.tileHeight)
                } placeholder: {
                    Color.white.opacity(0.08)
                        .frame(maxWidth: .infinity, maxHeight: m.tileHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: m.tileHeight)
                .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .center, endPoint: .bottom)

                HStack {
                    Text(channel.title)
                        .font(m.tileTitleFont)
                        .lineLimit(1)
                    Spacer()
                    if isOffline {
                        Text("OFFLINE")
                            .font(m.tileOfflineFont)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, m.tileOfflineHPadding)
                            .padding(.vertical, m.tileOfflineVPadding)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(m.tilePadding)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(m.tileFavoriteFont)
                        .foregroundStyle(.yellow)
                        .padding(m.tilePadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: m.tileHeight)
            .clipShape(RoundedRectangle(cornerRadius: m.tileCornerRadius))
            .foregroundStyle(.white)
            .opacity(isOffline ? 0.6 : 1.0)
            .grayscale(isOffline ? 1.0 : 0.0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if let onToggleFavorite {
                Button {
                    onToggleFavorite()
                } label: {
                    Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
                }
            }
            if let onRename {
                Button {
                    onRename()
                } label: {
                    Label("Rename...", systemImage: "pencil")
                }
            }
            if let onToggleLive {
                Button {
                    onToggleLive()
                } label: {
                    Label(channel.isLiveExpected ? "Mark as VOD" : "Mark as Live",
                          systemImage: channel.isLiveExpected ? "video" : "livephoto")
                }
            }
            if let onRemove {
                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }
}
