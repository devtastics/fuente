import AppKit
import FuenteWorkspace

/// A project window: navigator on the left, editors on the right. Xcode's layout, one window per folder.
final class ProjectWindowController: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    let workspace: Workspace
    private let navigator: NavigatorViewController
    private let editorArea = EditorAreaViewController()
    private let splitViewController = NSSplitViewController()
    private let stateStore = WorkspaceStateStore.default
    private var saveStateTask: Task<Void, Never>?

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
        workspace.onFoldersChanged = { [weak self] nodes in self?.navigator.reload(nodes) }
        workspace.onDocumentsChangedOnDisk = { [weak self] documents in
            // Xcode's rule: unmodified documents follow the disk; edited ones keep the user's version.
            for document in documents where !document.isDirty {
                (try? self?.editorArea.editor(for: document))?.reloadFromDisk()
            }
        }
        workspace.startWatching()
        navigator.onExpansionChange = { [weak self] in self?.scheduleStateSave() }
        restoreState()
        editorArea.tabBar.onSelect = { [weak self] document in self?.activate(document) }
        editorArea.tabBar.onClose = { [weak self] document in self?.close(document) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("ProjectWindowController does not support NSCoding") }

    /// Opens a file inside this project and shows it.
    func open(_ url: URL) {
        do {
            let document = try workspace.open(url)
            try editorArea.show(document, in: workspace)
            navigator.reveal(url)
            updateTitle()
            scheduleStateSave()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func activate(_ document: Document) {
        workspace.activate(document)
        do { try editorArea.show(document, in: workspace) } catch { NSAlert(error: error).runModal(); return }
        if let url = document.url { navigator.reveal(url) }
        updateTitle()
        scheduleStateSave()
    }

    /// Closes a tab, asking about unsaved changes first.
    func close(_ document: Document) {
        if document.isDirty {
            switch UnsavedChangesAlert.run(for: [document.name]) {
            case .save: guard (try? editorArea.editor(for: document))?.save() == true else { return }
            case .discard: break
            case .cancel: return
            }
        }
        workspace.close(document)
        editorArea.remove(document)
        try? editorArea.show(workspace.activeDocument, in: workspace)
        if let url = workspace.activeDocument?.url { navigator.reveal(url) }
        updateTitle()
        scheduleStateSave()
    }

    @objc func closeTab(_ sender: Any?) {
        if let document = workspace.activeDocument {
            close(document)
        } else {
            window?.performClose(sender)
        }
    }

    @objc func selectNextTab(_ sender: Any?) { selectTab(offset: 1) }
    @objc func selectPreviousTab(_ sender: Any?) { selectTab(offset: -1) }

    private func selectTab(offset: Int) {
        let documents = workspace.documents
        guard let active = workspace.activeDocument, let index = documents.firstIndex(where: { $0 === active }), documents.count > 1 else { return }
        activate(documents[(index + offset + documents.count) % documents.count])
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

    // MARK: - Remembered state

    private func restoreState() {
        guard let state = stateStore.load(for: workspace.rootURL) else { return }
        let folders = workspace.restore(state)
        navigator.expand(folders)
        try? editorArea.show(workspace.activeDocument, in: workspace)
        if let url = workspace.activeDocument?.url { navigator.reveal(url) }
        updateTitle()
    }

    /// Saves half a second after the last change, so a burst of changes writes once and a crash loses little.
    private func scheduleStateSave() {
        saveStateTask?.cancel()
        saveStateTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveState()
        }
    }

    private func saveState() {
        let state = workspace.state(expandedFolders: navigator.expandedFolders)
        try? stateStore.save(state, for: workspace.rootURL)
    }

    // MARK: - Toolbar

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    // MARK: - Closing

    func windowWillClose(_ notification: Notification) {
        saveStateTask?.cancel()
        saveState()
        workspace.stopWatching()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        let dirty = workspace.documents.filter(\.isDirty)
        guard !dirty.isEmpty else { return true }
        switch UnsavedChangesAlert.run(for: dirty.map(\.name)) {
        case .save: return dirty.allSatisfy { (try? editorArea.editor(for: $0))?.save() == true }
        case .discard: return true
        case .cancel: return false
        }
    }
}
