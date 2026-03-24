import SwiftUI

@main
struct MakerDesktopApp: App {
    @StateObject private var store = WorkspaceDashboardStore()

    var body: some Scene {
        WindowGroup("Maker Studio") {
            WorkspaceDashboardView(store: store)
                .frame(minWidth: 1360, minHeight: 880)
        }
        .defaultSize(width: 1423, height: 899)
        .windowResizability(.contentMinSize)
    }
}
