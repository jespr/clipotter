import SwiftUI
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct ClipOtterApp: App {
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
            CommandGroup(replacing: .appInfo) {
                Button("About ClipOtter") {
                    NSApp.orderFrontStandardAboutPanel(options: [.credits: Self.aboutCredits])
                }
            }
            #if canImport(Sparkle)
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
            #endif
        }
    }

    private static var aboutCredits: NSAttributedString {
        let credits = NSMutableAttributedString()
        let bodyFont = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let center = NSMutableParagraphStyle()
        center.alignment = .center

        func appendLink(_ title: String, url: String) {
            credits.append(NSAttributedString(string: title, attributes: [
                .link: URL(string: url) as Any,
                .font: bodyFont,
                .paragraphStyle: center,
            ]))
        }

        appendLink("clipotter.app", url: "https://clipotter.app")
        credits.append(NSAttributedString(string: "\n", attributes: [.font: bodyFont, .paragraphStyle: center]))
        appendLink("@jespr on X", url: "https://x.com/jespr")
        return credits
    }
}
