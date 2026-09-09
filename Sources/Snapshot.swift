import AppKit
import CoreGraphics

/// `Tide --snapshot <dir>`: opens the sample document in an off-screen window and writes PNGs of the
/// UI (panel collapsed/expanded, dark mode, settings, equation editor) without disturbing the desktop.
enum Snapshot {
    private typealias CaptureFn = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    static func image(of window: NSWindow) -> CGImage? {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_NOW),
              let sym = dlsym(handle, "CGWindowListCreateImage") else { return nil }
        let fn = unsafeBitCast(sym, to: CaptureFn.self)
        // kCGWindowListOptionIncludingWindow, kCGWindowImageBoundsIgnoreFraming | kCGWindowImageBestResolution
        return fn(CGRect.null, 1 << 3, CGWindowID(window.windowNumber), (1 << 0) | (1 << 3))?.takeRetainedValue()
    }

    @discardableResult
    static func save(_ window: NSWindow?, to url: URL) -> Bool {
        guard let window, let cg = image(of: window) else { print("snapshot: could not capture \(url.lastPathComponent)"); return false }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        do { try png.write(to: url); print("snapshot: wrote \(url.path) (\(cg.width)x\(cg.height))"); return true } catch { print("snapshot: \(error)"); return false }
    }

    static func run(outputDir: String) {
        let dir = URL(fileURLWithPath: outputDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dc = NSDocumentController.shared
        guard let doc = try? dc.makeUntitledDocument(ofType: DocFormat.docx.identifier) as? TideDocument else { print("snapshot: no document"); exit(1) }
        doc.content = SampleDocument.make(typography: .current, renderEquations: true)
        dc.addDocument(doc)
        doc.makeWindowControllers()
        guard let wc = doc.windowControllers.first as? DocumentWindowController, let window = wc.window else { print("snapshot: no window"); exit(1) }
        NSApp.appearance = NSAppearance(named: .aqua)
        let offscreen = NSRect(x: -3400, y: 120, width: 1180, height: 820)
        window.setFrame(offscreen, display: true)
        doc.showWindows()
        window.setFrame(offscreen, display: true)

        // Only take keyboard focus if nobody is using the Mac right now.
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        if idle > 45 { NSApp.activate(ignoringOtherApps: true) }

        let editor = wc.editor
        editor.textView.setSelectedRange(NSRange(location: 60, length: 0))
        let delegate = NSApp.delegate as? AppDelegate

        var t: TimeInterval = 1.4
        func step(_ delay: TimeInterval, _ block: @escaping () -> Void) {
            t += delay
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: block)
        }
        step(0) { editor.forceExpanded = true; window.displayIfNeeded() }
        step(1.0) { save(window, to: dir.appendingPathComponent("tide-panel-expanded.png")) }
        step(0.1) { editor.forceExpanded = false }
        step(0.9) { save(window, to: dir.appendingPathComponent("tide-panel-collapsed.png")) }
        step(0.1) { editor.textView.scrollToEndOfDocument(nil) }
        step(0.8) { save(window, to: dir.appendingPathComponent("tide-bottom.png")) }
        step(0.1) { editor.textView.scrollToBeginningOfDocument(nil) }
        step(0.1) { NSApp.appearance = NSAppearance(named: .darkAqua); editor.forceExpanded = true }
        step(1.2) { save(window, to: dir.appendingPathComponent("tide-dark.png")) }
        step(0.1) {
            editor.forceExpanded = false
            delegate?.showSettings(nil)
            delegate?.settingsWindowIfLoaded?.setFrameOrigin(NSPoint(x: -3400, y: 900))
        }
        step(1.0) { save(delegate?.settingsWindowIfLoaded, to: dir.appendingPathComponent("tide-settings.png")) }
        step(0.1) {
            delegate?.settingsWindowIfLoaded?.orderOut(nil)
            editor.equationRequest = EquationRequest(source: "x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}", display: true, replaceRange: nil)
        }
        step(1.6) { save(window.attachedSheet, to: dir.appendingPathComponent("tide-equation.png")) }
        step(0.3) {
            NSApp.appearance = nil
            print("snapshot: done")
            exit(0)
        }
    }
}
