import AppKit
import FuenteWorkspace

/// A window for a single file opened outside any project.
final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private let editor: EditorViewController

    init(fileURL: URL?) throws {
        editor = EditorViewController(document: try Document(url: fileURL))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("EditorWindow")
        super.init(window: window)

        window.delegate = self
        window.title = editor.document.name
        window.representedURL = fileURL
        window.contentViewController = editor
        window.setContentSize(NSSize(width: 900, height: 640))
        window.initialFirstResponder = editor.textView
        window.center()
        editor.onChange = { [weak self] editor in
            self?.window?.isDocumentEdited = editor.document.isDirty
            self?.window?.title = editor.document.name
            self?.window?.representedURL = editor.document.url
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorWindowController does not support NSCoding") }

    @objc func saveDocument(_ sender: Any?) {
        editor.save()
    }

    /// A single-file window has no tabs: closing the tab closes the window.
    @objc func closeTab(_ sender: Any?) {
        window?.performClose(sender)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard editor.document.isDirty else { return true }
        switch UnsavedChangesAlert.run(for: [editor.document.name]) {
        case .save: return editor.save()
        case .discard: return true
        case .cancel: return false
        }
    }
}
