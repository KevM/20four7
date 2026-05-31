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

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .bottomLeading) {
                AsyncImage(url: channel.resolvedThumbnailURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.white.opacity(0.08)
                }
                .frame(height: 96)
                .clipped()

                LinearGradient(colors: [.clear, .black.opacity(0.8)],
                               startPoint: .center, endPoint: .bottom)

                HStack {
                    Text(channel.title).font(.caption.weight(.semibold)).lineLimit(1)
                    Spacer()
                    if isOffline {
                        Text("OFFLINE")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                .padding(8)

                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.caption2).foregroundStyle(.yellow)
                        .padding(8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(height: 96)
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
