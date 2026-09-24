import AppKit
import FuenteText

/// One window showing one file. The seed of the editor shell.
final class EditorWindowController: NSWindowController {
    private let fileURL: URL?

    init(fileURL: URL?) {
        self.fileURL = fileURL
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = .unified
        window.tabbingMode = .preferred
        window.setFrameAutosaveName("EditorWindow")
        super.init(window: window)

        window.title = fileURL?.lastPathComponent ?? "Untitled"
        window.representedURL = fileURL
        let contentView = makeContentView()
        window.contentView = contentView
        window.initialFirstResponder = contentView.documentView
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("EditorWindowController does not support NSCoding") }

    private func makeContentView() -> NSScrollView {
        let text = fileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        let textView = TextView(storage: TextStorage(text), typesetter: LineTypesetter(font: font))

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.documentView = textView
        return scrollView
    }
}
