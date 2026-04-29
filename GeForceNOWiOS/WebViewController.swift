import UIKit
import WebKit
import SafariServices

final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, SFSafariViewControllerDelegate {
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private var safariController: SFSafariViewController?
    private var webViewProgressObservation: NSKeyValueObservation?

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
        impactFeedback.prepare()
        loadGeForceNow()
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
            impactFeedback.impactOccurred()
            impactFeedback.prepare()
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
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        setLoadingProgress(1.0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        setLoadingProgress(1.0)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        setLoadingProgress(1.0)
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
        override(navigator, 'standalone', true);
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
      };

      const installHaptics = () => {
        const trigger = () => window.webkit?.messageHandlers?.haptic?.postMessage('tap');
        const shouldTrigger = (el) => !!el.closest('button, [role="button"], a, input[type="button"], input[type="submit"]');

        document.addEventListener('pointerdown', (event) => {
          if (shouldTrigger(event.target)) trigger();
        }, { passive: true, capture: true });

        document.addEventListener('keydown', (event) => {
          if ((event.key === 'Enter' || event.key === ' ') && shouldTrigger(event.target)) trigger();
        }, { passive: true, capture: true });
      };

      applyNativeLikeControls();
      patchNavigator();
      forceInlineVideo();
      patchPwaSignals();
      installHaptics();
    })();
    """
}
