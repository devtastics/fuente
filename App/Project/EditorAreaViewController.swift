import AppKit
import FuenteWorkspace

/// Tabs on top, one editor per open document below, showing the active one.
@MainActor
final class EditorAreaViewController: NSViewController {
    let tabBar = TabBarView()
    private let container = NSView()
    private var editors: [Document.ID: EditorViewController] = [:]
    private(set) var activeEditor: EditorViewController?
    private let placeholder = NSTextField(labelWithString: "No Editor")

    /// Called after any change in any editor.
    var onChange: ((EditorViewController) -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        tabBar.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        placeholder.font = .systemFont(ofSize: 28, weight: .light)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tabBar)
        view.addSubview(container)
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            // The window's content extends under the toolbar; start below it.
            tabBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBar.heightAnchor.constraint(equalToConstant: TabBarView.height),
            container.topAnchor.constraint(equalTo: tabBar.bottomAnchor),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func editor(for document: Document) -> EditorViewController {
        if let existing = editors[document.id] { return existing }
        let editor = EditorViewController(document: document)
        editor.onChange = { [weak self] in
            self?.tabBar.refresh()
            self?.onChange?($0)
        }
        editors[document.id] = editor
        return editor
    }

    /// Shows `document` and rebuilds the tabs from the workspace's document list.
    func show(_ document: Document?, in workspace: Workspace) {
        if let active = activeEditor {
            active.view.removeFromSuperview()
            active.removeFromParent()
            activeEditor = nil
        }
        tabBar.reload(documents: workspace.documents, active: document)
        tabBar.isHidden = workspace.documents.isEmpty
        guard let document else {
            placeholder.isHidden = false
            return
        }
        placeholder.isHidden = true
        let editor = editor(for: document)
        addChild(editor)
        editor.view.frame = container.bounds
        editor.view.autoresizingMask = [.width, .height]
        container.addSubview(editor.view)
        activeEditor = editor
        view.window?.makeFirstResponder(editor.textView)
    }

    func remove(_ document: Document) {
        editors[document.id] = nil
    }
}
