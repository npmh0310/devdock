import SwiftUI

@main
struct DevDockApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar only: all UI lives in the dropdown panel.
        Settings { EmptyView() }
    }
}
