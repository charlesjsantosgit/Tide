import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var documentController: TideDocumentController!
    private var settingsWindow: NSWindow?
    private var helpWindow: NSWindow?
    private var testMode = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        documentController = TideDocumentController()
        NSApp.mainMenu = MainMenu.build()
        let args = CommandLine.arguments
        let switches = ["--selftest", "--snapshot", "--eqdebug", "--dump", "--version", "--quit-after-launch", "--update-check", "--update-dryrun", "--update-now"]
        testMode = args.contains(where: { switches.contains($0) })
        if testMode { NSApp.setActivationPolicy(.accessory) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            SelfTest.run()
        } else if let i = args.firstIndex(of: "--eqdebug"), i + 1 < args.count {
            SelfTest.equationDebug(outputDir: args[i + 1])
        } else if let i = args.firstIndex(of: "--dump"), i + 1 < args.count {
            SelfTest.dump(path: args[i + 1])
        } else if args.contains("--version") {
            print("Tide \(Updater.currentVersion)")
            exit(0)
        } else if args.contains("--quit-after-launch") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
        } else if let i = args.firstIndex(where: { ["--update-check", "--update-dryrun", "--update-now"].contains($0) }) {
            let feed = i + 1 < args.count ? args[i + 1] : Updater.defaultFeed
            Updater.runCommandLine(mode: args[i], feed: feed)
        } else if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.run(outputDir: args[i + 1])
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { Updater.shared.checkAutomaticallyIfDue() }
        }
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !testMode }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) { FileChipCell.stopAll() }

    // MARK: Windows

    @objc func showSettings(_ sender: Any?) {
        if settingsWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 500, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Tide Settings"
            w.contentViewController = NSHostingController(rootView: SettingsView())
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var settingsWindowIfLoaded: NSWindow? { settingsWindow }

    @objc func showTideHelp(_ sender: Any?) {
        if helpWindow == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            w.title = "Tide Help"
            w.contentViewController = NSHostingController(rootView: HelpView())
            w.isReleasedWhenClosed = false
            w.center()
            helpWindow = w
        }
        helpWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showAbout(_ sender: Any?) {
        let credits = NSAttributedString(string: "A small, glassy word processor.\nWrites real Word documents.", attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits, .applicationName: "Tide"])
    }

    @objc func checkForUpdates(_ sender: Any?) { Updater.shared.check(userInitiated: true) }

    // MARK: View menu

    @objc func togglePanel(_ sender: Any?) { Settings.panelHidden.toggle() }
    @objc func setPanelSide(_ sender: NSMenuItem) { Settings.panelSide = sender.tag == 0 ? .left : .right }
    @objc func toggleWordCount(_ sender: Any?) { Settings.showWordCount.toggle() }
    @objc func zoomIn(_ sender: Any?) { Settings.zoom = min(3, Settings.zoom + 0.25) }
    @objc func zoomOut(_ sender: Any?) { Settings.zoom = max(0.5, Settings.zoom - 0.25) }
    @objc func zoomActual(_ sender: Any?) { Settings.zoom = 1.0 }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(togglePanel(_:)):
            menuItem.title = Settings.panelHidden ? "Show Panel" : "Hide Panel"
        case #selector(setPanelSide(_:)):
            menuItem.state = (Settings.panelSide == .left) == (menuItem.tag == 0) ? .on : .off
        case #selector(toggleWordCount(_:)):
            menuItem.state = Settings.showWordCount ? .on : .off
        default:
            break
        }
        return true
    }
}
