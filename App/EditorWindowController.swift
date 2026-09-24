import AppKit
import FuenteText

/// One window showing one file. The seed of the editor shell.
final class EditorWindowController: NSWindowController, NSWindowDelegate, TextViewDelegate {
    private var fileURL: URL?
    private let textView: TextView

    init(fileURL: URL?) {
        self.fileURL = fileURL
        let text = fileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: font))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("EditorWindow")
        super.init(window: window)

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        textView.installGutter()

        window.delegate = self
        window.title = fileURL?.lastPathComponent ?? "Untitled"
        window.representedURL = fileURL
        window.contentView = scrollView
        window.initialFirstResponder = textView
        window.center()
        textView.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorWindowController does not support NSCoding") }

    // MARK: - Saving

    func textViewDidChangeText(_ textView: TextView) {
        window?.isDocumentEdited = true
    }

    @objc func saveDocument(_ sender: Any?) {
        save()
    }

    /// Writes the document. Returns false if the user cancelled the save panel or the write failed.
    @discardableResult
    private func save() -> Bool {
        if fileURL == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Untitled.txt"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            fileURL = url
            window?.title = url.lastPathComponent
            window?.representedURL = url
        }
        guard let fileURL else { return false }
        do {
            try textView.layoutManager.storage.string.write(to: fileURL, atomically: true, encoding: .utf8)
            window?.isDocumentEdited = false
            return true
        } catch {
            let alert = NSAlert(error: error)
            alert.runModal()
            return false
        }
    }

    // MARK: - Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.isDocumentEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(sender.title)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Don’t Save")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertThirdButtonReturn: return true
        default: return false
        }
    }
}
