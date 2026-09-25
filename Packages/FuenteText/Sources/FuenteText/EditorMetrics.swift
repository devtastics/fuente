import Foundation
import os

/// Live numbers about the engine, for the development HUD. Signposts go to Instruments in parallel.
@MainActor
public final class EditorMetrics {
    public static let shared = EditorMetrics()

    public static let signposter = OSSignposter(subsystem: "com.devtastics.fuente", category: "editor")

    public private(set) var lastDrawDuration: Duration = .zero
    public private(set) var lastLayoutDuration: Duration = .zero
    public private(set) var lastEditDuration: Duration = .zero
    public private(set) var lastHighlightDuration: Duration = .zero
    public private(set) var lastHighlightSpanCount = 0

    /// Lines with real glyph runs versus lines still on the estimated height, for the front-most view.
    public private(set) var typesetLineCount = 0
    public private(set) var totalLineCount = 0

    private init() {}

    func recordDraw(_ duration: Duration) { lastDrawDuration = duration }
    func recordLayout(_ duration: Duration) { lastLayoutDuration = duration }
    func recordEdit(_ duration: Duration) { lastEditDuration = duration }
    func recordLines(typeset: Int, total: Int) {
        typesetLineCount = typeset
        totalLineCount = total
    }

    public func recordHighlight(_ duration: Duration, spans: Int) {
        lastHighlightDuration = duration
        lastHighlightSpanCount = spans
    }
}
