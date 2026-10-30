import SwiftUI

@main
struct PocketFilmLabApp: App {
    var body: some Scene {
        WindowGroup {
            // Edge to edge: the page pads itself with env(safe-area-inset-*).
            WebView().ignoresSafeArea()
        }
    }
}
