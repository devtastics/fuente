import AppKit
import FuenteSyntax
import FuenteText

// Usage: ViewHarness [--empty | --nstextview] [--huge] [--gutter] [--php] [--nolayer] [--seconds N]
// Opens one window and exits after N seconds (default 30), so a script can sample it in between.
let arguments = Set(CommandLine.arguments.dropFirst())
func flag(_ name: String) -> Bool { arguments.contains("--\(name)") }
let seconds = CommandLine.arguments.firstIndex(of: "--seconds").flatMap { Int(CommandLine.arguments[$0 + 1]) } ?? 30

let hugeText = (0..<100_000).map { "    $line\($0) = compute(\($0), \"text\"); // comment \($0)" }.joined(separator: "\n")
let smallText = "<?php\necho 'hola';\n"

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 640), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
window.title = "ViewHarness " + arguments.sorted().joined(separator: " ")
let scrollView = NSScrollView()
scrollView.hasVerticalScroller = true
var highlighter: SyntaxHighlighter?

if flag("empty") {
    window.contentView = NSView()
} else if flag("nstextview") {
    let textView = NSTextView(frame: window.contentView!.bounds)
    textView.string = flag("huge") ? hugeText : smallText
    textView.isVerticallyResizable = true
    textView.autoresizingMask = [.width]
    scrollView.documentView = textView
    window.contentView = scrollView
} else {
    let textView = TextView(storage: TextStorage(flag("huge") ? hugeText : smallText))
    if flag("nolayer") { textView.wantsLayer = false }
    scrollView.documentView = textView
    if flag("gutter") { textView.installGutter() }
    if flag("php") { highlighter = SyntaxHighlighter(textView: textView, language: Languages.php, theme: .system) }
    // Experiments: a second draw half a second in, invalidating everything or only what is visible.
    if flag("redraw-all") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { textView.needsDisplay = true } }
    if flag("redraw-visible") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { textView.setNeedsDisplay(textView.visibleRect) } }
    window.contentView = scrollView
}

window.makeKeyAndOrderFront(nil)
let launch = ContinuousClock.now
@MainActor func report(_ label: String) {
    let m = EditorMetrics.shared
    print("HARNESS \(label): draws=\(m.drawCount) layouts=\(m.layoutCount) highlight=\(m.lastHighlightDuration) typeset=\(m.typesetLineCount)/\(m.totalLineCount)")
}
DispatchQueue.main.asyncAfter(deadline: .now() + 1) { report("1 s") }
DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { report("\(seconds) s"); app.terminate(nil) }
app.run()
