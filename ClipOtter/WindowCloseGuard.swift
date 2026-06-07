import SwiftUI
import AppKit

/// Installs an `NSWindowDelegate` that intercepts the window's close button to
/// offer saving the current session when there are unsaved changes.
struct WindowCloseGuard: NSViewRepresentable {
    var hasUnsavedChanges: () -> Bool
    var onSave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { context.coordinator.attach(to: view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hasUnsavedChanges = hasUnsavedChanges
        context.coordinator.onSave = onSave
        context.coordinator.attach(to: nsView.window)
    }

    final class Coordinator: NSObject, NSWindowDelegate {
        var hasUnsavedChanges: () -> Bool = { false }
        var onSave: () -> Void = {}
        private weak var window: NSWindow?

        func attach(to window: NSWindow?) {
            guard let window, self.window !== window else { return }
            self.window = window
            window.delegate = self
        }

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            guard hasUnsavedChanges() else { return true }

            let alert = NSAlert()
            alert.messageText = "Save this session before closing?"
            alert.informativeText = "You can reopen this transcript, starred lines, and processed output later."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Don't Save")
            alert.addButton(withTitle: "Cancel")

            switch alert.runModal() {
            case .alertFirstButtonReturn:
                onSave()
                return true
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
    }
}
