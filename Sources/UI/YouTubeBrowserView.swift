import SwiftUI
import WebKit

enum AddFlowDestination: Hashable {
    case addChannelForm(urlText: String, title: String, startTime: Double)
}

enum WebViewAction: Equatable {
    case idle
    case goBack
    case goForward
    case reload
}

struct YouTubeBrowserView: View {
    let store: ChannelStore
    let localStore: LocalStore
    let onSaved: () -> Void
    let onWatchNow: (Channel, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass
    private var m: LayoutMetrics { LayoutMetrics(hSizeClass) }

    @State private var path = NavigationPath()
    @State private var webView: WKWebView? = nil

    @State private var currentURL: URL? = nil
    @State private var currentTitle = ""
    @State private var canGoBack = false
    @State private var canGoForward = false
    @State private var isLoading = false
    @State private var action: WebViewAction = .idle

    @State private var isValidating = false
    @State private var errorMessage: String? = nil

    var initialURL: URL {
        // Default to "jelly cam live" with live stream filter
        let query = "jelly cam live".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://m.youtube.com/results?search_query=\(query)&sp=EgJAAQ%3D%3D")!
    }

    var activeVideoID: String? {
        guard let url = currentURL else { return nil }
        if case .video(let id) = YouTubeURLParser.parse(url.absoluteString) {
            return id
        }
        return nil
    }

    var cleanTitle: String {
        var title = currentTitle
        if title.hasSuffix(" - YouTube") {
            title = String(title.dropLast(10))
        }
        return title
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                YouTubeBrowserWebView(
                    initialURL: initialURL,
                    webView: $webView,
                    currentURL: $currentURL,
                    currentTitle: $currentTitle,
                    canGoBack: $canGoBack,
                    canGoForward: $canGoForward,
                    isLoading: $isLoading,
                    action: $action
                )
                .ignoresSafeArea(edges: .bottom)

                if let videoID = activeVideoID {
                    VStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Text("Video page detected")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(cleanTitle)
                                .font(m.browserTitleFont)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Button {
                                selectVideo(videoID: videoID)
                            } label: {
                                HStack {
                                    if isValidating {
                                        ProgressView()
                                            .controlSize(.small)
                                            .padding(.trailing, 8)
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    Text("Select Video")
                                        .font(m.browserOverlayButtonFont)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            .disabled(isValidating)

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(m.browserOverlayPadding)
                        .background(VisualEffectView(effect: UIBlurEffect(style: .systemMaterial)))
                        .cornerRadius(m.browserOverlayCornerRadius)
                        .shadow(radius: 10)
                        .padding(.horizontal, m.browserOverlayPadding)
                        .padding(.bottom, m.browserOverlayPadding)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Browse YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        action = .goBack
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(!canGoBack)

                    Button {
                        action = .goForward
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(!canGoForward)

                    Button {
                        action = .reload
                    } label: {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }

                    Button {
                        path.append(AddFlowDestination.addChannelForm(urlText: "", title: "", startTime: 0.0))
                    } label: {
                        Label("Paste Link", systemImage: "link")
                    }
                }
            }
            .navigationDestination(for: AddFlowDestination.self) { dest in
                switch dest {
                case .addChannelForm(let urlText, let title, let startTime):
                    AddChannelView(
                        store: store,
                        localStore: localStore,
                        initialURLText: urlText,
                        initialTitle: title,
                        startTime: startTime,
                        onSaved: onSaved,
                        onWatchNow: onWatchNow
                    )
                }
            }
        }
    }

    private func selectVideo(videoID: String) {
        isValidating = true
        errorMessage = nil

        Task {
            let startTime: Double
            if let webView = self.webView {
                let timeResult = try? await webView.evaluateJavaScript("document.querySelector('video') ? document.querySelector('video').currentTime : 0") as? Double
                startTime = timeResult ?? 0.0
            } else {
                startTime = 0.0
            }

            let result = await ChannelValidator.validateVideoEmbeddability(videoID: videoID)
            isValidating = false

            switch result {
            case .success(let officialTitle):
                let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
                path.append(AddFlowDestination.addChannelForm(urlText: url.absoluteString, title: officialTitle, startTime: startTime))
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
    }
}

struct YouTubeBrowserWebView: UIViewRepresentable {
    let initialURL: URL
    @Binding var webView: WKWebView?
    @Binding var currentURL: URL?
    @Binding var currentTitle: String
    @Binding var canGoBack: Bool
    @Binding var canGoForward: Bool
    @Binding var isLoading: Bool
    @Binding var action: WebViewAction

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        context.coordinator.setupObservers(webView: webView)

        let request = URLRequest(url: initialURL)
        webView.load(request)

        DispatchQueue.main.async {
            self.webView = webView
        }

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if action == .goBack {
            if uiView.canGoBack {
                uiView.goBack()
            }
            DispatchQueue.main.async { action = .idle }
        } else if action == .goForward {
            if uiView.canGoForward {
                uiView.goForward()
            }
            DispatchQueue.main.async { action = .idle }
        } else if action == .reload {
            uiView.reload()
            DispatchQueue.main.async { action = .idle }
        }
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var parent: YouTubeBrowserWebView
        var observers: [NSKeyValueObservation] = []

        init(_ parent: YouTubeBrowserWebView) {
            self.parent = parent
        }

        func setupObservers(webView: WKWebView) {
            observers = [
                webView.observe(\.url, options: .new) { [weak self] webView, _ in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.parent.currentURL = webView.url
                    }
                },
                webView.observe(\.title, options: .new) { [weak self] webView, _ in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.parent.currentTitle = webView.title ?? ""
                    }
                },
                webView.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.parent.canGoBack = webView.canGoBack
                    }
                },
                webView.observe(\.canGoForward, options: .new) { [weak self] webView, _ in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.parent.canGoForward = webView.canGoForward
                    }
                },
                webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
                    guard let self = self else { return }
                    DispatchQueue.main.async {
                        self.parent.isLoading = webView.isLoading
                    }
                }
            ]
        }

        deinit {
            observers.forEach { $0.invalidate() }
        }

        @available(iOS 15.0, *)
        @MainActor
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
        ) {
            decisionHandler(.grant)
        }
    }
}

struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: UIViewRepresentableContext<Self>) -> UIVisualEffectView { UIVisualEffectView() }
    func updateUIView(_ uiView: UIVisualEffectView, context: UIViewRepresentableContext<Self>) { uiView.effect = effect }
}
