import AppKit

/// The application menu bar. Built in code: no storyboards, no nibs.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(appMenu())
        menu.addItem(fileMenu())
        menu.addItem(editMenu())
        menu.addItem(windowMenu())
        return menu
    }

    private static func appMenu() -> NSMenuItem {
        let submenu = NSMenu()
        submenu.addItem(withTitle: "About Fuente", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Hide Fuente", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Quit Fuente", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return item(submenu)
    }

    private static func fileMenu() -> NSMenuItem {
        let submenu = NSMenu(title: "File")
        submenu.addItem(withTitle: "Open…", action: #selector(AppDelegate.openDocument(_:)), keyEquivalent: "o")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        submenu.addItem(withTitle: "Save", action: #selector(EditorWindowController.saveDocument(_:)), keyEquivalent: "s")
        return item(submenu)
    }

    private static func editMenu() -> NSMenuItem {
        let submenu = NSMenu(title: "Edit")
        submenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        submenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        submenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        submenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        submenu.addItem(.separator())
        submenu.addItem(withTitle: "Select All", action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        return item(submenu)
    }

    private static func windowMenu() -> NSMenuItem {
        let submenu = NSMenu(title: "Window")
        submenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        submenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = submenu
        return item(submenu)
    }

    private static func item(_ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = submenu
        return item
    }
}
