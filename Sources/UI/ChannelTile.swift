import SwiftUI

struct ChannelTile: View {
    let channel: Channel
    let isFavorite: Bool
    let onTap: () -> Void

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
                    if channel.isLiveExpected {
                        Text("● LIVE").font(.caption2.weight(.bold)).foregroundStyle(.red)
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
        }
        .buttonStyle(.plain)
    }
}
