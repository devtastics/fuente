import AppKit
import CoreText

/// Lays out a single line of text into fragments with CoreText, wrapping at a given width if asked.
public struct LineTypesetter {
    public var font: NSFont
    public var attributes: [NSAttributedString.Key: Any]

    public init(font: NSFont = .monospacedSystemFont(ofSize: 12, weight: .regular)) {
        self.font = font
        // Unstyled text takes the fill color of the drawing context, so the view controls the default color.
        self.attributes = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String): true,
        ]
    }

    /// Typesets `text` (a single line, no newline). `width` of `nil` means no wrapping.
    /// `styles` are UTF-16 ranges local to the line; later entries override earlier ones where they overlap.
    public func typeset(_ text: String, styles: [StyledRange] = [], width: CGFloat? = nil) -> [LineFragment] {
        let attributed = NSMutableAttributedString(string: text, attributes: attributes)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let fromContextKey = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        for style in styles {
            let clamped = style.range.clamped(to: 0..<attributed.length)
            guard !clamped.isEmpty else { continue }
            attributed.addAttribute(colorKey, value: style.color.cgColor, range: NSRange(clamped))
            attributed.removeAttribute(fromContextKey, range: NSRange(clamped))
        }
        let length = attributed.length
        guard length > 0 else { return [emptyFragment(attributed)] }

        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var fragments: [LineFragment] = []
        var start = 0
        while start < length {
            var count = length - start
            if let width {
                // Always consume at least one character so narrow widths cannot stall the loop.
                count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(width)))
            }
            let ctLine = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count))
            fragments.append(fragment(ctLine, range: start..<(start + count)))
            start += count
        }
        return fragments
    }

    private func fragment(_ ctLine: CTLine, range: Range<Int>) -> LineFragment {
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading)
        return LineFragment(
            ctLine: ctLine, range: range, width: CGFloat(width),
            ascent: ascent, descent: descent, leading: leading
        )
    }

    /// An empty line still occupies a row; CoreText reports zero metrics for it, so use the font's.
    private func emptyFragment(_ attributed: NSAttributedString) -> LineFragment {
        let ctLine = CTLineCreateWithAttributedString(attributed)
        return LineFragment(
            ctLine: ctLine, range: 0..<0, width: 0,
            ascent: font.ascender, descent: -font.descender, leading: font.leading
        )
    }
}
