import SwiftUI

@main
struct BinderyApp: App {
    @StateObject private var state = LibraryState()
    @StateObject private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup("Bindery") {
            LibraryView()
                .environmentObject(state)
                .environmentObject(appSettings)
                .frame(minWidth: 1120, minHeight: 780)
        }
        .defaultSize(width: 1180, height: 820)
        .windowStyle(.hiddenTitleBar)
    }
}
