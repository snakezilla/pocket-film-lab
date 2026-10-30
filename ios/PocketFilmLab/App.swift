import SwiftUI

@main
struct PocketFilmLabApp: App {
    var body: some Scene {
        WindowGroup {
            WebView().ignoresSafeArea(.container, edges: .bottom)
        }
    }
}
