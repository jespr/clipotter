import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct TranscriptApp: App {
    #if canImport(Sparkle)
    private let updaterController: SPUStandardUpdaterController

    init() {
        // Don't auto-check in debug builds (they aren't signed/notarized).
        #if DEBUG
        updaterController = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #else
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            #endif
        }
    }
}
