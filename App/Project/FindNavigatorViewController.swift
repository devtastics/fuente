import AppKit
import FuenteWorkspace

/// The Find navigator: a search field with options and results grouped by file.
@MainActor
final class FindNavigatorViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSSearchFieldDelegate {
    private let workspace: Workspace
    let searchField = NSSearchField()
    private let caseButton = NSButton(checkboxWithTitle: "Aa", target: nil, action: nil)
    private let wordButton = NSButton(checkboxWithTitle: "Word", target: nil, action: nil)
    private let regexButton = NSButton(checkboxWithTitle: ".*", target: nil, action: nil)
    private let summary = NSTextField(labelWithString: "")
    private let outlineView = NSOutlineView()
    private var results: [SearchFileResult] = []
    private var searchTask: Task<Void, Never>?

    var onSelectMatch: ((SearchMatch) -> Void)?

    init(workspace: Workspace) {
        self.workspace = workspace
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("FindNavigatorViewController does not support NSCoding") }

    override func loadView() {
        searchField.placeholderString = "Find in Project"
        searchField.delegate = self
        searchField.target = self
        searchField.action = #selector(runSearch)
        searchField.sendsWholeSearchString = true
        for button in [caseButton, wordButton, regexButton] {
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            button.target = self
            button.action = #selector(runSearch)
        }
        caseButton.toolTip = "Match Case"
        wordButton.toolTip = "Whole Words"
        regexButton.toolTip = "Regular Expression"
        summary.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        summary.textColor = .secondaryLabelColor

        let options = NSStackView(views: [caseButton, wordButton, regexButton, summary])
        options.orientation = .horizontal
        options.spacing = 8
        options.alignment = .centerY

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("match"))
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .sourceList
        outlineView.rowSizeStyle = .small
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.autoresizesOutlineColumn = true
        let scrollView = NSScrollView()
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false

        let stack = NSStackView(views: [searchField, options, scrollView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 0, right: 8)
        for subview in [searchField, options] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            subview.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -16).isActive = true
        }
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        view = stack
    }

    func focus() {
        view.window?.makeFirstResponder(searchField)
    }

    private var query: SearchQuery {
        SearchQuery(text: searchField.stringValue, isCaseSensitive: caseButton.state == .on,
                    matchesWholeWord: wordButton.state == .on, isRegex: regexButton.state == .on)
    }

    @objc private func runSearch() {
        searchTask?.cancel()
        results.removeAll()
        outlineView.reloadData()
        let query = query
        guard !query.text.isEmpty else { summary.stringValue = ""; return }
        summary.stringValue = "Searching…"
        let search = ProjectSearch(rootURL: workspace.rootURL)
        searchTask = Task { [weak self] in
            var files = 0, matches = 0
            for await result in search.results(for: query) {
                guard let self, !Task.isCancelled else { return }
                self.results.append(result)
                files += 1
                matches += result.matches.count
                self.outlineView.insertItems(at: IndexSet(integer: self.results.count - 1), inParent: nil, withAnimation: [])
                self.outlineView.expandItem(result)
                self.summary.stringValue = "\(matches) in \(files) files"
            }
            guard let self, !Task.isCancelled else { return }
            self.summary.stringValue = matches == 0 ? "No results" : "\(matches) in \(files) files"
        }
    }

    // MARK: - Outline

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        item == nil ? results.count : ((item as? SearchFileResult)?.matches.count ?? 0)
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        item == nil ? results[index] : (item as! SearchFileResult).matches[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { item is SearchFileResult }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        let identifier = NSUserInterfaceItemIdentifier("ResultCell")
        let cell = outlineView.makeView(withIdentifier: identifier, owner: nil) as? NSTableCellView ?? makeCell(identifier)
        if let file = item as? SearchFileResult {
            let relative = workspace.relativePath(for: file.url) ?? file.url.lastPathComponent
            cell.textField?.attributedStringValue = NSAttributedString(string: "\(relative)  ", attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .semibold)])
                + NSAttributedString(string: "\(file.matches.count)", attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.secondaryLabelColor])
            cell.imageView?.image = NSWorkspace.shared.icon(forFile: file.url.path)
        } else if let match = item as? SearchMatch {
            let trimmed = match.lineText.trimmingCharacters(in: .whitespaces)
            let leading = match.lineText.utf16.count - match.lineText.drop { $0 == " " || $0 == "\t" }.utf16.count
            let text = NSMutableAttributedString(string: "\(match.line + 1)  ", attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor])
            let lineAttributed = NSMutableAttributedString(string: trimmed, attributes: [.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)])
            let start = max(0, match.range.lowerBound - leading)
            let length = min(match.range.count, (trimmed as NSString).length - start)
            if length > 0 { lineAttributed.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: NSFont.smallSystemFontSize), range: NSRange(location: start, length: length)) }
            text.append(lineAttributed)
            cell.textField?.attributedStringValue = text
            cell.imageView?.image = nil
        }
        return cell
    }

    private func makeCell(_ identifier: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = identifier
        let imageView = NSImageView()
        let textField = NSTextField(labelWithString: "")
        textField.lineBreakMode = .byTruncatingTail
        cell.addSubview(imageView)
        cell.addSubview(textField)
        cell.imageView = imageView
        cell.textField = textField
        imageView.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            imageView.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 14),
            imageView.heightAnchor.constraint(equalToConstant: 14),
            textField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 4),
            textField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            textField.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let match = outlineView.item(atRow: outlineView.selectedRow) as? SearchMatch else { return }
        onSelectMatch?(match)
    }
}

private func + (lhs: NSAttributedString, rhs: NSAttributedString) -> NSAttributedString {
    let result = NSMutableAttributedString(attributedString: lhs)
    result.append(rhs)
    return result
}
