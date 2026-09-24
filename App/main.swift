import AppKit

// Nib-less entry point: create the delegate ourselves and hand control to AppKit.
let delegate = AppDelegate()
NSApplication.shared.delegate = delegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
