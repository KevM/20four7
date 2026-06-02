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
    @State private var validationError: VideoValidationError? = nil
    @State private var validatedTitle: String? = nil
    @State private var checkTask: Task<Void, Never>? = nil

    var initialURL: URL {
        // Default to "live nature" with live stream filter
        let query = "live nature".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
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
                    // A retryable error keeps the button live (tap re-runs the check);
                    // only a hard block (embedding disallowed) actually disables it.
                    let canRetry = validationError?.isRetryable ?? false
                    let isDisabled = isValidating || (validationError != nil && !canRetry)
                    let buttonTitle = isValidating ? "Checking Video..." : (canRetry ? "Try Again" : "Select Video")
                    VStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Text(cleanTitle)
                                .font(m.browserTitleFont)
                                .foregroundColor(.primary)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Button {
                                if canRetry {
                                    triggerEmbeddabilityCheck(videoID: videoID)
                                } else {
                                    selectVideo(videoID: videoID)
                                }
                            } label: {
                                HStack {
                                    if isValidating {
                                        ProgressView()
                                            .controlSize(.small)
                                            .padding(.trailing, 8)
                                    } else if canRetry {
                                        Image(systemName: "arrow.clockwise")
                                    } else {
                                        Image(systemName: "arrow.right.circle.fill")
                                    }
                                    Text(buttonTitle)
                                        .font(m.browserOverlayButtonFont)
                                }
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(isDisabled ? Color.white.opacity(0.15) : Color.blue)
                                .foregroundColor(isDisabled ? .secondary : .white)
                                .cornerRadius(10)
                            }
                            .disabled(isDisabled)

                            if let validationError {
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.white)
                                        .font(m.wide ? .body : .footnote)
                                        .padding(.top, 1)
                                    Text(validationError.localizedDescription)
                                        .font(m.wide ? .body : .footnote)
                                        .foregroundColor(.white)
                                        .multilineTextAlignment(.leading)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.85))
                                .cornerRadius(8)
                                .padding(.top, 4)
                            }
                        }
                        .padding(m.browserOverlayPadding)
                        .background(.ultraThinMaterial)
                        .cornerRadius(m.browserOverlayCornerRadius)
                        .shadow(radius: 10)
                        .padding(.horizontal, m.browserOverlayPadding)
                        .padding(.bottom, m.browserOverlayPadding)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .onChange(of: activeVideoID, initial: true) { _, newValue in
                if let newValue {
                    triggerEmbeddabilityCheck(videoID: newValue)
                } else {
                    resetValidation()
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
                        onWatchNow: onWatchNow,
                        onSearchMore: {
                            action = .goBack
                        }
                    )
                }
            }
        }
    }

    /// Proactively validates embeddability as soon as a video page is detected, so the
    /// overlay can surface an error (and disable the button) before the user taps it.
    /// On success the official title is cached in `validatedTitle` for `selectVideo`.
    ///
    /// A leading debounce keeps this cheap while browsing: each new video cancels the
    /// previous task before the sleep elapses, so only the video the user settles on
    /// actually hits the network.
    private func triggerEmbeddabilityCheck(videoID: String) {
        checkTask?.cancel()
        isValidating = true
        validationError = nil
        validatedTitle = nil

        checkTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }

            let result = await ChannelValidator.validateVideoEmbeddability(videoID: videoID)
            if Task.isCancelled { return }
            isValidating = false

            switch result {
            case .success(let officialTitle):
                validatedTitle = officialTitle
            case .failure(let error):
                validationError = error
            }
        }
    }

    /// Cancels any in-flight check and clears validation state (no active video).
    private func resetValidation() {
        checkTask?.cancel()
        isValidating = false
        validationError = nil
        validatedTitle = nil
    }

    private func selectVideo(videoID: String) {
        Task {
            let startTime: Double
            if let webView = self.webView {
                let timeResult = try? await webView.evaluateJavaScript("document.querySelector('video') ? document.querySelector('video').currentTime : 0") as? Double
                startTime = timeResult ?? 0.0
            } else {
                startTime = 0.0
            }

            let title = validatedTitle ?? cleanTitle
            let url = URL(string: "https://www.youtube.com/watch?v=\(videoID)")!
            path.append(AddFlowDestination.addChannelForm(urlText: url.absoluteString, title: title, startTime: startTime))
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
            let host = origin.host
            if host == "youtube.com" || host.hasSuffix(".youtube.com") {
                decisionHandler(.grant)
            } else {
                decisionHandler(.deny)
            }
        }
    }
}
