#if DEBUG
import AppKit
import FuenteText

/// Floating panel with process memory, CPU and the engine's timings. Debug builds only. Cmd+Opt+P.
@MainActor
final class PerformanceHUD: NSWindowController {
    static let shared = PerformanceHUD()

    private let label = NSTextField(wrappingLabelWithString: "")
    private var timer: Timer?
    private var lastCPUSeconds = ProcessStats.cpuSeconds()
    private var lastSampleTime = ContinuousClock.now
    private var cpuPercent = 0.0

    private init() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 230),
            styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.title = "Performance"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.setFrameAutosaveName("PerformanceHUD")
        super.init(window: panel)

        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            label.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
        ])
        panel.contentView = content
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("PerformanceHUD does not support NSCoding") }

    func toggle() {
        if window?.isVisible == true {
            close()
            timer?.invalidate()
            timer = nil
        } else {
            refresh()
            showWindow(nil)
            timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            }
        }
    }

    private func refresh() {
        let now = ContinuousClock.now
        let cpu = ProcessStats.cpuSeconds()
        let wall = Double((now - lastSampleTime).components.seconds) + Double((now - lastSampleTime).components.attoseconds) / 1e18
        if wall > 0.5 {
            cpuPercent = (cpu - lastCPUSeconds) / wall * 100
            lastCPUSeconds = cpu
            lastSampleTime = now
        }
        let memory = ProcessStats.memory()
        let metrics = EditorMetrics.shared
        label.stringValue = """
        Memory      \(format(bytes: memory.footprint)) footprint
                    \(format(bytes: memory.resident)) resident
        CPU         \(String(format: "%5.1f", cpuPercent)) %

        Draw        \(format(metrics.lastDrawDuration))
        Layout      \(format(metrics.lastLayoutDuration))
        Edit        \(format(metrics.lastEditDuration))
        Highlight   \(format(metrics.lastHighlightDuration))  \(metrics.lastHighlightSpanCount) spans
        Lines       \(metrics.typesetLineCount) typeset / \(metrics.totalLineCount)
        """
    }

    private func format(bytes: UInt64) -> String {
        String(format: "%7.1f MB", Double(bytes) / 1_048_576)
    }

    private func format(_ duration: Duration) -> String {
        let micros = Double(duration.components.seconds) * 1e6 + Double(duration.components.attoseconds) / 1e12
        return micros >= 1000 ? String(format: "%7.2f ms", micros / 1000) : String(format: "%7.0f µs", micros)
    }
}

/// Process-level numbers from Mach and the C library. Footprint is what Activity Monitor shows as Memory.
enum ProcessStats {
    static func memory() -> (footprint: UInt64, resident: UInt64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reboundPointer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), reboundPointer, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, 0) }
        return (UInt64(info.phys_footprint), UInt64(info.resident_size))
    }

    /// User plus system CPU time consumed by the whole process, in seconds.
    static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1e6
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1e6
        return user + system
    }
}
#endif
