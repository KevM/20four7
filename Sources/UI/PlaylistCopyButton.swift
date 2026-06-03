import SwiftUI

/// Copies the current filtered YouTube playlist URL to the clipboard, swapping
/// to a green checkmark for 1.5s as confirmation. Disabled when there is no
/// filtered playlist URL available.
///
/// Currently unreferenced. To restore it, drop it into the trailing toolbar:
///
///     ToolbarItem(placement: .topBarTrailing) {
///         PlaylistCopyButton(store: store)
///     }
///
/// The original design also showed a screen-level top toast. A toolbar button
/// cannot own a screen-level overlay, so re-wire it at the `RootView` level by
/// hoisting the `copiedPlaylist` flag up (e.g. via a binding) and re-adding:
///
///     .overlay(alignment: .top) {
///         if copiedPlaylist {
///             Text("Playlist URL copied to clipboard!")
///                 .font(.subheadline)
///                 .fontWeight(.medium)
///                 .foregroundColor(.white)
///                 .padding(.vertical, 8)
///                 .padding(.horizontal, 16)
///                 .background(Color.blue.opacity(0.9))
///                 .cornerRadius(20)
///                 .transition(.move(edge: .top).combined(with: .opacity))
///                 .padding(.top, 12)
///         }
///     }
struct PlaylistCopyButton: View {
    @ObservedObject var store: ChannelStore
    @State private var copiedPlaylist = false

    var body: some View {
        Button {
            if let url = store.filteredPlaylistURL {
                UIPasteboard.general.string = url.absoluteString
                withAnimation {
                    copiedPlaylist = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation {
                        copiedPlaylist = false
                    }
                }
            }
        } label: {
            if copiedPlaylist {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Image(systemName: "play.rectangle.on.rectangle")
            }
        }
        .disabled(store.filteredPlaylistURL == nil)
    }
}
