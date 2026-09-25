import AppKit
import FuenteWorkspace

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var fileWindows: [EditorWindowController] = []
    private var projectWindows: [ProjectWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        if fileWindows.isEmpty && projectWindows.isEmpty {
            openFileWindow(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    @objc func openDocument(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.message = "Open a folder as a project, or individual files."
        guard panel.runModal() == .OK else { return }
        panel.urls.forEach(open)
    }

    /// Folders become projects. Files open inside a project that contains them, or in their own window.
    func open(_ url: URL) {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if isDirectory {
            openProject(url)
        } else if let project = projectWindows.first(where: { $0.workspace.contains(url) }) {
            project.open(url)
            project.showWindow(nil)
        } else {
            openFileWindow(url)
        }
    }

    private func openProject(_ url: URL) {
        let root = url.standardizedFileURL
        if let existing = projectWindows.first(where: { $0.workspace.rootURL == root }) {
            existing.showWindow(nil)
            return
        }
        let controller = ProjectWindowController(workspace: Workspace(rootURL: root))
        projectWindows.append(controller)
        controller.showWindow(nil)
        NSDocumentController.shared.noteNewRecentDocumentURL(root)
    }

    private func openFileWindow(_ url: URL?) {
        do {
            let controller = try EditorWindowController(fileURL: url)
            fileWindows.append(controller)
            controller.showWindow(nil)
            if let url { NSDocumentController.shared.noteNewRecentDocumentURL(url) }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}
