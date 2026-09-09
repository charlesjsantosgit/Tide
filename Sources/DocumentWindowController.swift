import AppKit
import SwiftUI

final class DocumentWindowController: NSWindowController {
    let editor = EditorController()

    init(document: TideDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 820),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .visible
        window.minSize = NSSize(width: 720, height: 480)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        super.init(window: window)

        editor.document = document
        document.editor = editor
        let host = NSHostingController(rootView: DocumentView(editor: editor))
        host.sizingOptions = []
        host.safeAreaRegions = []
        window.contentViewController = host
        window.setContentSize(NSSize(width: 1180, height: 820))
        window.center()
        shouldCascadeWindows = true
        windowFrameAutosaveName = "TideDocumentWindow"

        if let content = window.contentView {
            editor.titlebarInset = max(0, content.bounds.height - window.contentLayoutRect.height)
        }
        editor.load(document.content)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String { displayName }
}
