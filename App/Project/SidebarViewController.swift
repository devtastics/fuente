import AppKit
import FuenteWorkspace

/// The left column: a switcher between the project tree and the find navigator, like Xcode's navigator bar.
@MainActor
final class SidebarViewController: NSViewController {
    enum Pane: Int { case files, find }

    let navigator: NavigatorViewController
    let find: FindNavigatorViewController
    private let switcher = NSSegmentedControl()
    private let container = NSView()
    private(set) var pane: Pane = .files

    init(workspace: Workspace) {
        navigator = NavigatorViewController(workspace: workspace)
        find = FindNavigatorViewController(workspace: workspace)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("SidebarViewController does not support NSCoding") }

    override func loadView() {
        view = NSView()
        switcher.segmentCount = 2
        switcher.setImage(NSImage(systemSymbolName: "folder", accessibilityDescription: "Project"), forSegment: 0)
        switcher.setImage(NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Find"), forSegment: 1)
        switcher.setToolTip("Project navigator", forSegment: 0)
        switcher.setToolTip("Find navigator", forSegment: 1)
        switcher.segmentStyle = .separated
        switcher.trackingMode = .selectOne
        switcher.selectedSegment = 0
        switcher.controlSize = .small
        switcher.target = self
        switcher.action = #selector(switcherChanged)
        switcher.translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(switcher)
        view.addSubview(container)
        NSLayoutConstraint.activate([
            switcher.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            switcher.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.topAnchor.constraint(equalTo: switcher.bottomAnchor, constant: 6),
            container.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            container.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            container.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        show(.files)
    }

    @objc private func switcherChanged() {
        show(Pane(rawValue: switcher.selectedSegment) ?? .files)
    }

    func show(_ pane: Pane) {
        self.pane = pane
        switcher.selectedSegment = pane.rawValue
        for child in children { child.view.removeFromSuperview(); child.removeFromParent() }
        let controller: NSViewController = pane == .files ? navigator : find
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: container.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }
}
