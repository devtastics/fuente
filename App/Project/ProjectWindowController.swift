import AppKit
import FuenteWorkspace

/// A project window: navigator on the left, editors on the right. Xcode's layout, one window per folder.
final class ProjectWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let workspace: Workspace
    private let navigator: NavigatorViewController
    private let editorArea = EditorAreaViewController()
    private let splitViewController = NSSplitViewController()

    init(workspace: Workspace) {
        self.workspace = workspace
        navigator = NavigatorViewController(workspace: workspace)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.toolbarStyle = .unified
        window.titleVisibility = .visible
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("ProjectWindow-\(workspace.rootURL.path)")
        super.init(window: window)

        let sidebar = NSSplitViewItem(sidebarWithViewController: navigator)
        sidebar.minimumThickness = 180
        sidebar.maximumThickness = 480
        sidebar.canCollapse = true
        let content = NSSplitViewItem(viewController: editorArea)
        content.minimumThickness = 400
        splitViewController.addSplitViewItem(sidebar)
        splitViewController.addSplitViewItem(content)

        let toolbar = NSToolbar(identifier: "ProjectToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.delegate = self
        window.contentViewController = splitViewController
        // A content view controller resizes the window to its view, which starts at zero.
        window.setContentSize(NSSize(width: 1100, height: 720))
        window.center()
        updateTitle()

        navigator.onSelectFile = { [weak self] url in self?.open(url) }
        editorArea.onChange = { [weak self] _ in self?.updateTitle() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ProjectWindowController does not support NSCoding") }

    /// Opens a file inside this project and shows it.
    func open(_ url: URL) {
        do {
            let document = try workspace.open(url)
            editorArea.show(document)
            navigator.reveal(url)
            updateTitle()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func updateTitle() {
        guard let window else { return }
        let document = workspace.activeDocument
        window.title = document?.name ?? workspace.name
        window.subtitle = document == nil ? "" : workspace.name
        window.representedURL = document?.url ?? workspace.rootURL
        window.isDocumentEdited = document?.isDirty ?? false
    }

    @objc func saveDocument(_ sender: Any?) {
        editorArea.activeEditor?.save()
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    // MARK: - Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let dirty = workspace.documents.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }
        switch UnsavedChangesAlert.run(for: dirty.map(\.name)) {
        case .save: return dirty.allSatisfy { editorArea.editor(for: $0).save() }
        case .discard: return true
        case .cancel: return false
        }
    }
}
