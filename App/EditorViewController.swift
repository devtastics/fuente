import AppKit
import FuenteSyntax
import FuenteText
import FuenteWorkspace

/// The editor for one document: text view, gutter and highlighter. Lives as long as the document is open.
@MainActor
final class EditorViewController: NSViewController, TextViewDelegate {
    let document: Document
    let textView: TextView
    private var highlighter: SyntaxHighlighter?

    /// Called after every text change, so the window can update its edited state.
    var onChange: ((EditorViewController) -> Void)?

    /// Reads the file once, into the editor's storage. The document keeps no copy.
    init(document: Document) throws {
        self.document = document
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView = TextView(storage: TextStorage(try document.read()), typesetter: LineTypesetter(font: font))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorViewController does not support NSCoding") }

    override func loadView() {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        textView.installGutter()
        textView.delegate = self
        view = scrollView

        if let ext = document.fileExtension, let language = Languages.language(forFileExtension: ext) {
            highlighter = SyntaxHighlighter(textView: textView, language: language, theme: .system)
            textView.lineCommentPrefix = language.lineComment
        }
    }

    /// Editor > Go to Line… (Cmd+L): a small sheet with a number field.
    @objc func goToLine(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Go to Line"
        alert.addButton(withTitle: "Go")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        field.placeholderString = "Line number"
        let current = textView.layoutManager.storage.line(at: textView.selection.head) + 1
        field.stringValue = String(current)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard let window = view.window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let line = Int(field.stringValue.trimmingCharacters(in: .whitespaces)), let self else { return }
            self.textView.goToLine(line)
            window.makeFirstResponder(self.textView)
        }
    }

    var text: String { textView.layoutManager.storage.string }

    private var isReloading = false

    func textViewDidChangeText(_ textView: TextView) {
        guard !isReloading else { return }
        document.markDirty()
        onChange?(self)
    }

    /// Takes the file's new contents from disk. Only called when the editor has no unsaved changes.
    func reloadFromDisk() {
        do {
            let text = try document.reloadFromDisk()
            isReloading = true
            textView.replaceAll(with: text)
            isReloading = false
            onChange?(self)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    /// Saves to the document's location, asking for one if it has none. False when cancelled or failed.
    @discardableResult
    func save() -> Bool {
        var destination: URL?
        if document.url == nil {
            let panel = NSSavePanel()
            panel.nameFieldStringValue = "Untitled.txt"
            guard panel.runModal() == .OK, let url = panel.url else { return false }
            destination = url
        }
        do {
            try document.save(text, to: destination)
            onChange?(self)
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }
}
