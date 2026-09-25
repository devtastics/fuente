import Foundation
import os

/// Live numbers about the engine, for the development HUD. Signposts go to Instruments in parallel.
@MainActor
public final class EditorMetrics {
    public static let shared = EditorMetrics()

    public static let signposter = OSSignposter(subsystem: "com.devtastics.fuente", category: "editor")

    public private(set) var lastDrawDuration: Duration = .zero
    public private(set) var lastLayoutDuration: Duration = .zero

    /// How many times any text view drew or laid out since launch. Bursts here mean redraw storms.
    public private(set) var drawCount = 0
    public private(set) var layoutCount = 0
    public private(set) var lastEditDuration: Duration = .zero
    public private(set) var lastHighlightDuration: Duration = .zero
    public private(set) var lastHighlightSpanCount = 0

    /// Lines with real glyph runs versus lines still on the estimated height, for the front-most view.
    public private(set) var typesetLineCount = 0
    public private(set) var totalLineCount = 0

    private init() {}

    /// Set FUENTE_TRACE=1 in the environment to log engine events to the unified log
    /// (`log show --predicate 'subsystem == "com.devtastics.fuente"' --last 1m`).
    public static let tracing = ProcessInfo.processInfo.environment["FUENTE_TRACE"] != nil
    private static let logger = Logger(subsystem: "com.devtastics.fuente", category: "trace")

    public static func trace(_ message: @autoclosure () -> String) {
        guard tracing else { return }
        let text = message()
        logger.notice("\(text, privacy: .public)")
    }

    func recordDraw(_ duration: Duration) { lastDrawDuration = duration; drawCount += 1 }
    func recordLayout(_ duration: Duration) { lastLayoutDuration = duration; layoutCount += 1 }
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
