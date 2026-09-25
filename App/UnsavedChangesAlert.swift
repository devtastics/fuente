import AppKit

/// The standard "save changes?" sheet, for one or several documents.
@MainActor
enum UnsavedChangesAlert {
    enum Choice { case save, discard, cancel }

    static func run(for names: [String]) -> Choice {
        let alert = NSAlert()
        if names.count == 1 {
            alert.messageText = "Do you want to save the changes made to “\(names[0])”?"
        } else {
            alert.messageText = "You have \(names.count) documents with unsaved changes. Do you want to save them?"
        }
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: names.count == 1 ? "Save" : "Save All")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: names.count == 1 ? "Don’t Save" : "Discard Changes")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .save
        case .alertThirdButtonReturn: return .discard
        default: return .cancel
        }
    }
}
