import SwiftUI

@main
struct EngraveApp: App {
    var body: some Scene {
        WindowGroup("Engrave") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1100, height: 700)
    }
}
