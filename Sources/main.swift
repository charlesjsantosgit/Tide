import AppKit

// Tide — a small, glassy word processor for macOS Tahoe.
// AppKit document architecture underneath, SwiftUI (Liquid Glass) on top.
let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
