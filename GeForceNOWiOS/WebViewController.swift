import UIKit
import WebKit
import SafariServices

final class WebViewController: UIViewController, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)

    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContentController = WKUserContentController()
        userContentController.add(self, name: "haptic")
        userContentController.add(self, name: "external")

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
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        impactFeedback.prepare()
        loadGeForceNow()
    }

    private func loadGeForceNow() {
        guard let url = URL(string: "https://play.geforcenow.com/mall/") else { return }
        webView.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30))
    }

    private func shouldOpenExternally(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return !host.hasSuffix("geforcenow.com")
    }

    private func presentSafariPopup(for url: URL) {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = false

        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = .white
        safari.preferredBarTintColor = .black
        present(safari, animated: true)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "haptic" {
            impactFeedback.impactOccurred()
            impactFeedback.prepare()
            return
        }

        if message.name == "external", let urlString = message.body as? String, let url = URL(string: urlString) {
            presentSafariPopup(for: url)
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if shouldOpenExternally(url) {
            presentSafariPopup(for: url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, shouldOpenExternally(url) {
            presentSafariPopup(for: url)
        }
        return nil
    }

    deinit {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "haptic")
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "external")
    }

    private static let androidUserAgent = "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.002) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.6367.82 Mobile Safari/537.36"

    private static let injectedScript = """
    (() => {
      const openExternal = (url) => {
        if (!url) return;
        try {
          window.webkit?.messageHandlers?.external?.postMessage(String(url));
        } catch (_) {}
      };

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

        const originalOpen = window.open?.bind(window);
        window.open = (url, target, features) => {
          if (typeof url === 'string' && /^https?:/i.test(url) && !/\.geforcenow\.com/i.test(url)) {
            openExternal(url);
            return null;
          }
          return originalOpen ? originalOpen(url, target, features) : null;
        };

        document.addEventListener('click', (event) => {
          const link = event.target?.closest?.('a[href]');
          if (!link) return;
          const href = link.getAttribute('href');
          if (!href || !/^https?:/i.test(href) || /\.geforcenow\.com/i.test(href)) return;
          event.preventDefault();
          openExternal(href);
        }, true);

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

      const persistCookiesToStorage = () => {
        const save = () => {
          try {
            localStorage.setItem('__gfn_cookie_cache', document.cookie);
          } catch (_) {}
        };

        save();
        setInterval(save, 2000);
      };

      patchNavigator();
      patchPwaSignals();
      applyNativeLikeControls();
      installHaptics();
      persistCookiesToStorage();
    })();
    """
}
