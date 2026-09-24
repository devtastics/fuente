import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [EditorWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        if windowControllers.isEmpty {
            openWindow(with: nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { openWindow(with: url) }
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.sourceCode, .plainText, .data]
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { openWindow(with: url) }
    }

    private func openWindow(with url: URL?) {
        let controller = EditorWindowController(fileURL: url)
        windowControllers.append(controller)
        controller.showWindow(nil)
    }
}
