import UIKit
import WebKit
import SafariServices

final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, SFSafariViewControllerDelegate, UIGestureRecognizerDelegate {
    private let lightImpactFeedback = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpactFeedback = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpactFeedback = UIImpactFeedbackGenerator(style: .heavy)
    private let softImpactFeedback = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpactFeedback = UIImpactFeedbackGenerator(style: .rigid)
    private let selectionFeedback = UISelectionFeedbackGenerator()
    private let notificationFeedback = UINotificationFeedbackGenerator()
    private var safariController: SFSafariViewController?
    private var webViewProgressObservation: NSKeyValueObservation?

    private struct OverlayCombo {
        let id = UUID()
        var title: String
        var enabled: Bool
        var isCustom: Bool
    }

    private let defaultKeyboardCombos = ["Shift+F", "Ctrl+Shift+Esc", "Alt+Tab", "W", "A", "S", "D", "Space", "Enter"]
    private var overlayCombos: [OverlayCombo] = []
    private var overlayMenuView: UIView?
    private var overlayButtonPanel: UIView?
    private var buttonPanelWidthConstraint: NSLayoutConstraint?
    private var buttonPanelHeightConstraint: NSLayoutConstraint?
    private var buttonPanelButtonsStack: UIStackView?

    private let loadingBar: UIProgressView = {
        let progress = UIProgressView(progressViewStyle: .bar)
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.progressTintColor = UIColor(red: 0.46, green: 0.82, blue: 0.04, alpha: 1.0)
        progress.trackTintColor = UIColor(white: 0.08, alpha: 0.9)
        progress.progress = 0
        progress.alpha = 0
        return progress
    }()

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        config.allowsInlineMediaPlayback = true
        config.allowsAirPlayForMediaPlayback = false
        config.mediaTypesRequiringUserActionForPlayback = []

        let userContentController = WKUserContentController()
        userContentController.add(self, name: "haptic")

        let script = WKUserScript(source: Self.injectedScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(script)
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.allowsBackForwardNavigationGestures = false
        webView.customUserAgent = Self.androidUserAgent
        return webView
    }()

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        view.addSubview(webView)
        view.addSubview(loadingBar)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            loadingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            loadingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            loadingBar.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            loadingBar.heightAnchor.constraint(equalToConstant: 3)
        ])

        observeWebViewProgress()
        prepareHaptics()
        setupThreeFingerMenuGesture()
        setupOverlayButtonPanel()
        loadGeForceNow()
    }

    private func prepareHaptics() {
        [lightImpactFeedback, mediumImpactFeedback, heavyImpactFeedback, softImpactFeedback, rigidImpactFeedback].forEach { $0.prepare() }
        selectionFeedback.prepare()
        notificationFeedback.prepare()
    }

    private func loadGeForceNow() {
        guard let url = URL(string: "https://play.geforcenow.com/mall/") else { return }
        webView.load(URLRequest(url: url, cachePolicy: .reloadRevalidatingCacheData, timeoutInterval: 30))
    }

    private func observeWebViewProgress() {
        webViewProgressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
            self?.setLoadingProgress(Float(webView.estimatedProgress))
        }
    }

    private func setLoadingProgress(_ progress: Float) {
        let clampedProgress = max(0, min(progress, 1))
        if loadingBar.alpha == 0 {
            loadingBar.progress = 0
            UIView.animate(withDuration: 0.15) { self.loadingBar.alpha = 1 }
        }

        loadingBar.setProgress(clampedProgress, animated: true)

        if clampedProgress >= 1 {
            UIView.animate(withDuration: 0.25, delay: 0.2, options: [.curveEaseOut]) {
                self.loadingBar.alpha = 0
            } completion: { _ in
                self.loadingBar.progress = 0
            }
        }
    }

    private func setupThreeFingerMenuGesture() {
        overlayCombos = defaultKeyboardCombos.map { OverlayCombo(title: $0, enabled: true, isCustom: false) }
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleThreeFingerTap))
        gesture.numberOfTouchesRequired = 3
        gesture.delegate = self
        gesture.cancelsTouchesInView = false
        view.addGestureRecognizer(gesture)
    }

    @objc private func handleThreeFingerTap() {
        playHaptic("rigid")
        if overlayMenuView != nil {
            closeOverlayMenu()
        } else {
            presentOverlayMenu()
        }
    }

    private func presentOverlayMenu() {
        let container = UIView(frame: view.bounds)
        container.backgroundColor = UIColor.black.withAlphaComponent(0.72)
        container.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = UIColor(white: 0.1, alpha: 0.98)

        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "Overlay Menu"
        title.textColor = .white
        title.font = .boldSystemFont(ofSize: 20)

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setTitle("✕", for: .normal)
        close.titleLabel?.font = .boldSystemFont(ofSize: 24)
        close.tintColor = .white
        close.addAction(UIAction { [weak self] _ in self?.closeOverlayMenu() }, for: .touchUpInside)

        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 6
        renderMenuRows(in: stack)

        let input = UITextField()
        input.translatesAutoresizingMaskIntoConstraints = false
        input.backgroundColor = UIColor(white: 0.2, alpha: 1.0)
        input.textColor = .white
        input.autocorrectionType = .no
        input.autocapitalizationType = .none
        input.placeholder = "Add combo (e.g. Shift+F)"
        input.attributedPlaceholder = NSAttributedString(string: "Add combo (e.g. Shift+F)", attributes: [.foregroundColor: UIColor.lightGray])
        input.layer.cornerRadius = 10
        input.setLeftPaddingPoints(10)

        let addButton = UIButton(type: .system)
        addButton.translatesAutoresizingMaskIntoConstraints = false
        addButton.setTitle("Add", for: .normal)
        addButton.tintColor = .white
        addButton.backgroundColor = UIColor(white: 0.25, alpha: 1.0)
        addButton.addAction(UIAction { [weak self, weak input, weak stack] _ in
            guard let self, let text = input?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            self.overlayCombos.append(OverlayCombo(title: text, enabled: true, isCustom: true))
            self.renderMenuRows(in: stack)
            self.refreshOverlayPanelButtons()
            input?.text = nil
            self.playHaptic("selection")
        }, for: .touchUpInside)

        container.addSubview(card)
        card.addSubview(title)
        card.addSubview(close)
        card.addSubview(stack)
        card.addSubview(input)
        card.addSubview(addButton)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            card.centerYAnchor.constraint(equalTo: container.centerYAnchor),

            title.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            title.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),

            close.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
            close.centerYAnchor.constraint(equalTo: title.centerYAnchor),

            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            input.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 14),
            input.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            input.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            input.heightAnchor.constraint(equalToConstant: 40),

            addButton.topAnchor.constraint(equalTo: input.bottomAnchor, constant: 10),
            addButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            addButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            addButton.heightAnchor.constraint(equalToConstant: 42),
            addButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        view.addSubview(container)
        overlayMenuView = container
    }

    private func closeOverlayMenu() {
        overlayMenuView?.removeFromSuperview()
        overlayMenuView = nil
    }

    private func renderMenuRows(in stack: UIStackView?) {
        guard let stack else { return }
        stack.arrangedSubviews.forEach { v in stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for combo in overlayCombos {
            stack.addArrangedSubview(makeComboRow(combo: combo))
        }
    }

    private func makeComboRow(combo: OverlayCombo) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6

        let send = makeSimpleButton(title: combo.title, bg: combo.enabled ? UIColor(white: 0.22, alpha: 1) : UIColor(white: 0.14, alpha: 1))
        send.addAction(UIAction { [weak self] _ in
            guard combo.enabled else { return }
            self?.sendKeyboardCombo(combo.title)
            self?.playHaptic("medium")
        }, for: .touchUpInside)
        row.addArrangedSubview(send)

        let toggle = makeSimpleButton(title: combo.enabled ? "ON" : "OFF", bg: UIColor(white: 0.3, alpha: 1))
        toggle.widthAnchor.constraint(equalToConstant: 46).isActive = true
        toggle.addAction(UIAction { [weak self, weak row] _ in
            guard let self, let i = self.overlayCombos.firstIndex(where: { $0.id == combo.id }) else { return }
            self.overlayCombos[i].enabled.toggle()
            if let superStack = row?.superview as? UIStackView { self.renderMenuRows(in: superStack) }
            self.refreshOverlayPanelButtons()
        }, for: .touchUpInside)
        row.addArrangedSubview(toggle)

        if combo.isCustom {
            let delete = makeSimpleButton(title: "DEL", bg: UIColor(white: 0.3, alpha: 1))
            delete.widthAnchor.constraint(equalToConstant: 52).isActive = true
            delete.addAction(UIAction { [weak self, weak row] _ in
                guard let self else { return }
                self.overlayCombos.removeAll(where: { $0.id == combo.id })
                if let superStack = row?.superview as? UIStackView { self.renderMenuRows(in: superStack) }
                self.refreshOverlayPanelButtons()
                self.playHaptic("warning")
            }, for: .touchUpInside)
            row.addArrangedSubview(delete)
        }
        return row
    }

    private func makeSimpleButton(title: String, bg: UIColor) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.heightAnchor.constraint(equalToConstant: 36).isActive = true
        button.backgroundColor = bg
        button.tintColor = .white
        return button
    }

    private func setupOverlayButtonPanel() {
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        view.addSubview(panel)
        buttonPanelWidthConstraint = panel.widthAnchor.constraint(equalToConstant: 180)
        buttonPanelHeightConstraint = panel.heightAnchor.constraint(equalToConstant: 220)
        NSLayoutConstraint.activate([
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            buttonPanelWidthConstraint!, buttonPanelHeightConstraint!
        ])
        let stack = UIStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.spacing = 4
        panel.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: panel.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8),
            stack.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -20)
        ])
        let handle = UIView()
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.backgroundColor = .white
        panel.addSubview(handle)
        NSLayoutConstraint.activate([
            handle.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -2),
            handle.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -2),
            handle.widthAnchor.constraint(equalToConstant: 14),
            handle.heightAnchor.constraint(equalToConstant: 14)
        ])
        handle.addGestureRecognizer(UIPanGestureRecognizer(target: self, action: #selector(handlePanelResizePan(_:))))
        buttonPanelButtonsStack = stack
        overlayButtonPanel = panel
        refreshOverlayPanelButtons()
    }

    @objc private func handlePanelResizePan(_ gesture: UIPanGestureRecognizer) {
        let t = gesture.translation(in: view)
        let w = max(120, min(360, (buttonPanelWidthConstraint?.constant ?? 180) + t.x))
        let h = max(120, min(500, (buttonPanelHeightConstraint?.constant ?? 220) + t.y))
        buttonPanelWidthConstraint?.constant = w
        buttonPanelHeightConstraint?.constant = h
        gesture.setTranslation(.zero, in: view)
    }

    private func refreshOverlayPanelButtons() {
        guard let stack = buttonPanelButtonsStack else { return }
        stack.arrangedSubviews.forEach { v in stack.removeArrangedSubview(v); v.removeFromSuperview() }
        for combo in overlayCombos where combo.enabled {
            let button = makeSimpleButton(title: combo.title, bg: UIColor(white: 0.2, alpha: 1))
            button.addAction(UIAction { [weak self] _ in self?.sendKeyboardCombo(combo.title); self?.playHaptic("light") }, for: .touchUpInside)
            stack.addArrangedSubview(button)
        }
    }

    private func sendKeyboardCombo(_ combo: String) {
        let escaped = combo
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        webView.evaluateJavaScript("window.__nativeKeyboardOverlayDispatch && window.__nativeKeyboardOverlayDispatch(\"\(escaped)\")")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool { true }

    func handleExternalReturn(url: URL) {
        safariController?.dismiss(animated: true)
        safariController = nil

        if let callback = extractWebCallbackURL(from: url) {
            webView.load(URLRequest(url: callback))
        }
    }

    private func extractWebCallbackURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let encodedTarget = components.queryItems?.first(where: { $0.name == "target" })?.value,
              let decoded = encodedTarget.removingPercentEncoding,
              let callbackURL = URL(string: decoded),
              ["http", "https"].contains(callbackURL.scheme?.lowercased() ?? "") else {
            return nil
        }

        return callbackURL
    }

    private func shouldKeepInsideWebView(_ url: URL) -> Bool {
        return isHTTPScheme(url)
    }

    private func isHTTPScheme(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return true }
        return scheme == "http" || scheme == "https"
    }

    private func shouldOpenInSafariViewController(_ url: URL) -> Bool {
        return false
    }

    private func presentSafariPopup(for url: URL) {
        guard safariController == nil, isHTTPScheme(url) else { return }

        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = false

        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = .white
        safari.preferredBarTintColor = .black
        safari.delegate = self
        safariController = safari
        present(safari, animated: true)
    }

    func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
        if safariController === controller {
            safariController = nil
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "haptic" {
            let type = message.body as? String ?? "tap"
            playHaptic(type)
        }
    }

    private func playHaptic(_ type: String) {
        switch type {
        case "selection":
            selectionFeedback.selectionChanged()
            selectionFeedback.prepare()
        case "success":
            notificationFeedback.notificationOccurred(.success)
            notificationFeedback.prepare()
        case "warning":
            notificationFeedback.notificationOccurred(.warning)
            notificationFeedback.prepare()
        case "error":
            notificationFeedback.notificationOccurred(.error)
            notificationFeedback.prepare()
        case "heavy":
            heavyImpactFeedback.impactOccurred(intensity: 1.0)
            heavyImpactFeedback.prepare()
        case "medium":
            mediumImpactFeedback.impactOccurred(intensity: 0.9)
            mediumImpactFeedback.prepare()
        case "rigid":
            rigidImpactFeedback.impactOccurred(intensity: 1.0)
            rigidImpactFeedback.prepare()
        case "soft":
            softImpactFeedback.impactOccurred(intensity: 0.8)
            softImpactFeedback.prepare()
        default:
            lightImpactFeedback.impactOccurred(intensity: 0.7)
            lightImpactFeedback.prepare()
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if shouldOpenInSafariViewController(url) {
            presentSafariPopup(for: url)
            decisionHandler(.cancel)
            return
        }

        if !shouldKeepInsideWebView(url) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            }
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let targetURL = navigationAction.request.url {
            webView.load(URLRequest(url: targetURL))
        }
        return nil
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        setLoadingProgress(0.05)
        playHaptic("soft")
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setLoadingProgress(1.0)
        playHaptic("success")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        setLoadingProgress(1.0)
        playHaptic("warning")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        setLoadingProgress(1.0)
        playHaptic("error")
    }

    deinit {
        webViewProgressObservation?.invalidate()
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "haptic")
    }

    private static let androidUserAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.002) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36"

    private static let injectedScript = """
    (() => {
      const applyNativeLikeControls = () => {
        const meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no, viewport-fit=cover';
        document.head.appendChild(meta);

        const style = document.createElement('style');
        style.innerHTML = `
          * {
            -webkit-user-select: none !important;
            user-select: none !important;
            -webkit-touch-callout: none !important;
            -webkit-tap-highlight-color: transparent !important;
          }
          html, body {
            overscroll-behavior: none !important;
            touch-action: manipulation !important;
          }
          input, textarea, [contenteditable='true'] {
            -webkit-user-select: text !important;
            user-select: text !important;
          }
          video {
            object-fit: fill !important;
          }
        `;
        document.head.appendChild(style);
      };

      const patchNavigator = () => {
        const override = (target, prop, value) => {
          try {
            Object.defineProperty(target, prop, { get: () => value, configurable: true });
          } catch (_) {}
        };

        override(navigator, 'platform', 'Linux armv8l');
        override(navigator, 'maxTouchPoints', 10);
        override(navigator, 'userAgent', 'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.002) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36');
        override(navigator, 'vendor', 'Google Inc.');
        override(navigator, 'appVersion', '5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.002) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36');
        override(navigator, 'standalone', true);
        override(window, 'isSecureContext', true);
        override(navigator, 'webdriver', false);
        override(navigator, 'language', 'en-US');
        override(navigator, 'languages', ['en-US', 'en']);
      };

      const forceInlineVideo = () => {
        const apply = (video) => {
          try {
            video.setAttribute('playsinline', '');
            video.setAttribute('webkit-playsinline', '');
            video.removeAttribute('autoplay');
            video.disablePictureInPicture = true;
            video.controls = false;
          } catch (_) {}
        };

        document.querySelectorAll('video').forEach(apply);
        const observer = new MutationObserver(() => {
          document.querySelectorAll('video').forEach(apply);
        });
        observer.observe(document.documentElement, { childList: true, subtree: true });
      };

      const patchPwaSignals = () => {
        const standaloneMql = {
          matches: true,
          media: '(display-mode: standalone)',
          onchange: null,
          addListener: () => {},
          removeListener: () => {},
          addEventListener: () => {},
          removeEventListener: () => {},
          dispatchEvent: () => false
        };

        const originalMatchMedia = window.matchMedia?.bind(window);
        window.matchMedia = (query) => {
          if (query === '(display-mode: standalone)' || query === '(display-mode: fullscreen)' || query === '(display-mode: minimal-ui)') {
            return standaloneMql;
          }
          return originalMatchMedia ? originalMatchMedia(query) : standaloneMql;
        };

        try {
          Object.defineProperty(document, 'referrer', { get: () => 'android-app://com.nvidia.geforcenow', configurable: true });
        } catch (_) {}

        try {
          Object.defineProperty(document, 'visibilityState', { get: () => 'visible', configurable: true });
          Object.defineProperty(document, 'hidden', { get: () => false, configurable: true });
        } catch (_) {}

        const fauxManifest = {
          name: 'GeForce NOW',
          short_name: 'GFN',
          display: 'standalone',
          start_url: '/',
          scope: '/',
          theme_color: '#76b900',
          background_color: '#000000'
        };

        const manifestBlob = new Blob([JSON.stringify(fauxManifest)], { type: 'application/manifest+json' });
        const manifestUrl = URL.createObjectURL(manifestBlob);
        let manifestEl = document.querySelector('link[rel="manifest"]');
        if (!manifestEl) {
          manifestEl = document.createElement('link');
          manifestEl.setAttribute('rel', 'manifest');
          document.head.appendChild(manifestEl);
        }
        manifestEl.setAttribute('href', manifestUrl);
        navigator.getInstalledRelatedApps = () => Promise.resolve([
          {
            platform: 'webapp',
            url: location.origin,
            id: 'geforcenow-standalone'
          }
        ]);

        if (!navigator.serviceWorker) {
          Object.defineProperty(navigator, 'serviceWorker', {
            configurable: true,
            get: () => ({
              controller: { state: 'activated' },
              ready: Promise.resolve({ scope: location.origin + '/' }),
              register: () => Promise.resolve({ scope: location.origin + '/' }),
              getRegistration: () => Promise.resolve({ scope: location.origin + '/' }),
              getRegistrations: () => Promise.resolve([{ scope: location.origin + '/' }]),
              addEventListener: () => {},
              removeEventListener: () => {}
            })
          });
        }
      };

      const installKeyboardOverlayBridge = () => {
        window.__nativeKeyboardOverlayDispatch = (combo) => {
          if (!combo || typeof combo !== 'string') return;
          const parts = combo.split('+').map(part => part.trim()).filter(Boolean);
          const key = parts[parts.length - 1] || '';
          const lower = parts.map(part => part.toLowerCase());
          const options = {
            key,
            bubbles: true,
            cancelable: true,
            ctrlKey: lower.includes('ctrl') || lower.includes('control'),
            shiftKey: lower.includes('shift'),
            altKey: lower.includes('alt') || lower.includes('option'),
            metaKey: lower.includes('meta') || lower.includes('cmd') || lower.includes('command')
          };
          const active = document.activeElement || document.body;
          active.dispatchEvent(new KeyboardEvent('keydown', options));
          active.dispatchEvent(new KeyboardEvent('keypress', options));
          active.dispatchEvent(new KeyboardEvent('keyup', options));
        };
      };

      const installHaptics = () => {
        const trigger = (type = 'tap') => window.webkit?.messageHandlers?.haptic?.postMessage(type);
        const shouldTrigger = (el) => !!el.closest('button, [role="button"], a, input[type="button"], input[type="submit"]');

        document.addEventListener('pointerdown', (event) => {
          if (shouldTrigger(event.target)) trigger('tap');
        }, { passive: true, capture: true });

        document.addEventListener('pointerup', (event) => {
          if (shouldTrigger(event.target)) trigger('selection');
        }, { passive: true, capture: true });

        document.addEventListener('keydown', (event) => {
          if ((event.key === 'Enter' || event.key === ' ') && shouldTrigger(event.target)) trigger('medium');
        }, { passive: true, capture: true });

        document.addEventListener('change', (event) => {
          const target = event.target;
          if (target?.matches?.('input, select, textarea')) trigger('selection');
        }, { passive: true, capture: true });

        document.addEventListener('submit', () => trigger('heavy'), { passive: true, capture: true });

        window.addEventListener('error', () => trigger('warning'), { passive: true });
        window.addEventListener('unhandledrejection', () => trigger('error'));
      };

      applyNativeLikeControls();
      patchNavigator();
      forceInlineVideo();
      patchPwaSignals();
      installKeyboardOverlayBridge();
      installHaptics();
    })();
    """
}


private extension UITextField {
    func setLeftPaddingPoints(_ amount: CGFloat) {
        let paddingView = UIView(frame: CGRect(x: 0, y: 0, width: amount, height: frame.size.height))
        leftView = paddingView
        leftViewMode = .always
    }
}
