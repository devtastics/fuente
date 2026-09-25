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
