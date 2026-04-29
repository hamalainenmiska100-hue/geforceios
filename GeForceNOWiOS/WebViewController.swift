import UIKit
import SafariServices

final class WebViewController: UIViewController {
    private var safariViewController: SFSafariViewController?

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        loadGeForceNow()
    }

    private func loadGeForceNow() {
        guard let url = URL(string: "https://play.geforcenow.com/mall/") else { return }

        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = false

        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.dismissButtonStyle = .close
        safari.preferredControlTintColor = .white
        safari.preferredBarTintColor = .black
        safari.modalPresentationStyle = .fullScreen

        addChild(safari)
        safari.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(safari.view)
        NSLayoutConstraint.activate([
            safari.view.topAnchor.constraint(equalTo: view.topAnchor),
            safari.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            safari.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            safari.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        safari.didMove(toParent: self)
        safariViewController = safari
    }
}
