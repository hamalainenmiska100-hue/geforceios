import UIKit
import WebKit

final class WebViewController: UIViewController, WKScriptMessageHandler {
    private let impactFeedback = UIImpactFeedbackGenerator(style: .light)
    private lazy var webView: WKWebView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        let userContentController = WKUserContentController()
        userContentController.add(self, name: "haptic")

        let script = WKUserScript(source: Self.injectedScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        userContentController.addUserScript(script)
        config.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.translatesAutoresizingMaskIntoConstraints = false
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

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "haptic" else { return }
        impactFeedback.impactOccurred()
        impactFeedback.prepare()
    }

    deinit {
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
