import AppKit
import FuenteWorkspace

/// Hosts one editor per open document and shows the active one.
@MainActor
final class EditorAreaViewController: NSViewController {
    private var editors: [Document.ID: EditorViewController] = [:]
    private(set) var activeEditor: EditorViewController?
    private let placeholder = NSTextField(labelWithString: "No Editor")

    /// Called after any change in any editor.
    var onChange: ((EditorViewController) -> Void)?

    override func loadView() {
        view = NSView()
        view.wantsLayer = true
        placeholder.font = .systemFont(ofSize: 28, weight: .light)
        placeholder.textColor = .tertiaryLabelColor
        placeholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholder.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }

    func editor(for document: Document) -> EditorViewController {
        if let existing = editors[document.id] { return existing }
        let editor = EditorViewController(document: document)
        editor.onChange = { [weak self] in self?.onChange?($0) }
        editors[document.id] = editor
        return editor
    }

    func show(_ document: Document?) {
        if let active = activeEditor {
            active.view.removeFromSuperview()
            active.removeFromParent()
            activeEditor = nil
        }
        guard let document else {
            placeholder.isHidden = false
            return
        }
        placeholder.isHidden = true
        let editor = editor(for: document)
        addChild(editor)
        editor.view.frame = view.bounds
        editor.view.autoresizingMask = [.width, .height]
        view.addSubview(editor.view)
        activeEditor = editor
        view.window?.makeFirstResponder(editor.textView)
    }

    func remove(_ document: Document) {
        editors[document.id] = nil
    }
}
