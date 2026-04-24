import SwiftUI

@main
struct MLXLauncherApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
    }
}
