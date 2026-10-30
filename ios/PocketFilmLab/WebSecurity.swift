import Foundation
import WebKit

/// The boundary of the privileged web view. Only the bundled page (app://local, main
/// frame) may talk to the native bridges; everything else is refused or sent out.
enum WebSecurity {
    static let scheme = "app"
    static let host = "local"

    /// True for a message from the bundled page's main frame. Messages from iframes
    /// (even same-origin ones) and from any other origin are refused.
    static func isTrustedSender(isMainFrame: Bool, scheme: String?, host: String?) -> Bool {
        isMainFrame && scheme?.lowercased() == Self.scheme && host?.lowercased() == Self.host
    }

    static func isTrusted(_ message: WKScriptMessage) -> Bool {
        let origin = message.frameInfo.securityOrigin
        return isTrustedSender(isMainFrame: message.frameInfo.isMainFrame, scheme: origin.protocol, host: origin.host)
    }

    enum NavigationDecision: Equatable {
        /// Load in the web view (only the bundled app://local pages).
        case allow
        /// Not loaded here; handed to the system (Safari) because the user followed a link.
        case openExternally
        /// Refused.
        case cancel
    }

    /// Navigation policy. The page is bundled, so the web view only ever loads
    /// app://local. A user-tapped https link in the main frame opens in Safari, outside
    /// the privileged view. Other schemes, other app:// hosts, http and anything an
    /// iframe tries to load from outside are refused.
    static func decide(url: URL?, isMainFrame: Bool, userTapped: Bool) -> NavigationDecision {
        guard let url, let scheme = url.scheme?.lowercased() else { return .cancel }
        if scheme == Self.scheme { return url.host?.lowercased() == Self.host ? .allow : .cancel }
        // about:blank / about:srcdoc frames are created by the page itself and carry its origin.
        if scheme == "about", !isMainFrame { return .allow }
        if scheme == "https", isMainFrame, userTapped { return .openExternally }
        return .cancel
    }

    /// Maps an app://local URL to a file under `root`, or nil if it is another host or
    /// would escape `root` (`..`, encoded `..`, symlinked siblings like `dist-evil`).
    static func resolve(_ url: URL, root: URL) -> URL? {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == Self.host else { return nil }
        let path = url.path.isEmpty || url.path == "/" ? "/index.html" : url.path
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let file = base.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        let prefix = base.path.hasSuffix("/") ? base.path : base.path + "/"
        guard file.path.hasPrefix(prefix) else { return nil }
        return file
    }
}
