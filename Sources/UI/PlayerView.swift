import SwiftUI
import UIKit

struct PlayerView: View {
    @ObservedObject var controller: PlaybackController
    @ObservedObject var store: ChannelStore
    let webView: WebViewPlayerService
    var settings: AppSettings
    let onClose: () -> Void

    @State private var overlayVisible = true
    @AppStorage("fillScreen") private var fillScreen = true
    @State private var hideTask: Task<Void, Never>? = nil
    @GestureState private var isHolding = false
    @State private var viewHeight: CGFloat = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            PlayerWebView(webView: webView.webView).ignoresSafeArea()

            if !overlayVisible {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation {
                            overlayVisible = true
                            resetHideTimer()
                        }
                    }
            }

            if overlayVisible {
                PlayerOverlay(
                    controller: controller,
                    showClock: settings.showClockOverlay,
                    dimOpacity: Double(settings.dimLevelRaw) * 0.2,
                    onSurf: { controller.surf($0) },
                    onToggleFavorite: { if let c = controller.currentChannel { store.toggleFavorite(c) } },
                    isFavorite: controller.currentChannel.map { store.isFavorite($0) } ?? false,
                    onStartSleep: { controller.startSleepTimer(seconds: Double(settings.defaultSleepMinutes) * 60) },
                    fillScreen: $fillScreen,
                    onInteraction: { resetHideTimer() },
                    onClose: onClose,
                    onGoLive: { controller.goLive() },
                    activeTag: activeCategoryName
                )
                .transition(.opacity)
            }

            if isHolding {
                HoldingOverlay(activeCategoryName: activeCategoryName)
                    .transition(.opacity)
            }
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { viewHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, h in viewHeight = h }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                overlayVisible.toggle()
                if overlayVisible {
                    resetHideTimer()
                } else {
                    hideTask?.cancel()
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .updating($isHolding) { _, state, _ in
                    state = true
                }
                .onEnded { value in
                    resetHideTimer()
                    // Ignore swipes that begin in the screen-edge zones iOS
                    // reserves for its own system gestures. Size the zones from
                    // the safe-area insets: the bottom inset is exactly the
                    // home-indicator region (where "swipe up to go home" was
                    // being mistaken for surf-next), the top inset the
                    // status-bar/notch region. On a device with no home
                    // indicator the bottom inset is 0, so nothing is excluded.
                    let insets = activeSafeAreaInsets
                    let startY = value.startLocation.y
                    let inBottomEdge = viewHeight > 0 && startY > viewHeight - insets.bottom
                    let inTopEdge = startY < insets.top
                    guard !inBottomEdge, !inTopEdge else { return }
                    if value.translation.height < -30 {
                        controller.surf(.next)
                    } else if value.translation.height > 30 {
                        controller.surf(.previous)
                    }
                }
        )
        .statusBarHidden(true)
        .onAppear {
            webView.setAspectCover(fillScreen)
            if overlayVisible {
                resetHideTimer()
            }
        }
        .onDisappear {
            hideTask?.cancel()
        }
        .onChange(of: fillScreen) {
            webView.setAspectCover(fillScreen)
        }
    }

    /// Safe-area insets of the active window. The bottom inset is the
    /// home-indicator region and the top inset the status-bar/notch region; the
    /// surf gesture uses them to stay out of iOS's own edge gestures without
    /// hardcoding pixel sizes. Falls back to `.zero` (no edge excluded).
    private var activeSafeAreaInsets: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private var activeCategoryName: String? {
        if store.selectedTagIDs.isEmpty {
            return nil
        }
        let resolved = store.selectedTagIDs.compactMap { store.tagsByID[$0]?.name }
        if resolved.isEmpty {
            return nil
        }
        return resolved.sorted().joined(separator: ", ")
    }

    private func resetHideTimer() {
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            guard !Task.isCancelled else { return }
            withAnimation {
                overlayVisible = false
            }
        }
    }
}

enum ArrowDirection {
    case up, down
}

struct AnimatedSurfArrow: View {
    let direction: ArrowDirection
    @State private var bounce = false
    
    var body: some View {
        VStack(spacing: 4) {
            if direction == .up {
                Image(systemName: "chevron.up")
                    .font(.system(size: 20, weight: .bold))
                Text("NEXT").font(.system(size: 9, weight: .semibold, design: .rounded))
            } else {
                Text("PREV").font(.system(size: 9, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.down")
                    .font(.system(size: 20, weight: .bold))
            }
        }
        .foregroundColor(.white)
        .shadow(color: .black.opacity(0.5), radius: 4, x: 0, y: 2)
        .offset(y: bounce ? (direction == .up ? -6 : 6) : 0)
        .opacity(bounce ? 1.0 : 0.4)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }
    }
}

struct HoldingOverlay: View {
    let activeCategoryName: String?
    
    var body: some View {
        ZStack {
            // Subtle dark vignette to make overlays readable
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // Top middle tag label
            if let categoryName = activeCategoryName {
                VStack {
                    Text(categoryName.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(.white.opacity(0.15), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.3), radius: 6, x: 0, y: 3)
                        .padding(.top, 24)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
            
            // Animated arrows at the top and bottom right
            VStack {
                HStack {
                    Spacer()
                    AnimatedSurfArrow(direction: .up)
                        .padding(.top, 40)
                        .padding(.trailing, 24)
                }
                Spacer()
                HStack {
                    Spacer()
                    AnimatedSurfArrow(direction: .down)
                        .padding(.bottom, 40)
                        .padding(.trailing, 24)
                }
            }
            .allowsHitTesting(false)
        }
    }
}
