import AppKit

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(editMenu())
        main.addItem(formatMenu())
        main.addItem(insertMenu())
        main.addItem(viewMenu())
        main.addItem(windowMenu())
        main.addItem(helpMenu())
        return main
    }

    // MARK: helpers

    private static func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0, target: AnyObject? = nil) -> NSMenuItem {
        let it = NSMenuItem(title: title, action: action, keyEquivalent: key)
        it.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        it.tag = tag
        it.target = target
        return it
    }

    private static func sel(_ name: String) -> Selector { Selector(name) }

    private static func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let menu = NSMenu(title: title)
        items.forEach { menu.addItem($0) }
        let it = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        it.submenu = menu
        return it
    }

    // MARK: menus

    private static func appMenu() -> NSMenuItem {
        let services = NSMenu(title: "Services")
        NSApp.servicesMenu = services
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        return submenu("Tide", [
            item("About Tide", #selector(AppDelegate.showAbout(_:))),
            item("Check for Updates…", #selector(AppDelegate.checkForUpdates(_:))),
            .separator(),
            item("Settings…", #selector(AppDelegate.showSettings(_:)), ","),
            .separator(),
            servicesItem,
            .separator(),
            item("Hide Tide", sel("hide:"), "h"),
            item("Hide Others", sel("hideOtherApplications:"), "h", [.command, .option]),
            item("Show All", sel("unhideAllApplications:")),
            .separator(),
            item("Quit Tide", sel("terminate:"), "q"),
        ])
    }

    private static func fileMenu() -> NSMenuItem {
        let recent = NSMenu(title: "Open Recent")
        recent.delegate = RecentDocumentsMenu.shared
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        let export = submenu("Export", [
            item("PDF…", #selector(TideDocument.exportPDF(_:))),
            item("Word Document (.docx)…", #selector(TideDocument.exportDocx(_:))),
            item("Rich Text (.rtf)…", #selector(TideDocument.exportRTF(_:))),
            item("Rich Text with Attachments (.rtfd)…", #selector(TideDocument.exportRTFD(_:))),
            item("Plain Text (.txt)…", #selector(TideDocument.exportTXT(_:))),
            item("Markdown (.md)…", #selector(TideDocument.exportMarkdown(_:))),
            item("Web Page (.html)…", #selector(TideDocument.exportHTML(_:))),
        ])
        let revert = submenu("Revert To", [
            item("Browse All Versions…", sel("browseDocumentVersions:")),
            item("Last Saved", sel("revertDocumentToSaved:")),
        ])
        return submenu("File", [
            item("New", sel("newDocument:"), "n"),
            item("Open…", sel("openDocument:"), "o"),
            recentItem,
            .separator(),
            item("Close", sel("performClose:"), "w"),
            item("Save", sel("saveDocument:"), "s"),
            item("Save As…", sel("saveDocumentAs:"), "S", [.command, .shift]),
            item("Duplicate", sel("duplicateDocument:")),
            item("Rename…", sel("renameDocument:")),
            item("Move To…", sel("moveDocument:")),
            revert,
            .separator(),
            item("Import…", #selector(TideDocument.importDocument(_:)), "I", [.command, .shift]),
            export,
            .separator(),
            item("Page Setup…", sel("runPageLayout:"), "P", [.command, .shift]),
            item("Print…", sel("printDocument:"), "p"),
        ])
    }

    private static func editMenu() -> NSMenuItem {
        let find = submenu("Find", [
            item("Find…", sel("performTextFinderAction:"), "f", tag: 1),
            item("Find and Replace…", sel("performTextFinderAction:"), "f", [.command, .option], tag: 12),
            item("Find Next", sel("performTextFinderAction:"), "g", tag: 2),
            item("Find Previous", sel("performTextFinderAction:"), "G", [.command, .shift], tag: 3),
            item("Use Selection for Find", sel("performTextFinderAction:"), "e", tag: 7),
            item("Jump to Selection", sel("centerSelectionInVisibleArea:"), "j"),
        ])
        let spelling = submenu("Spelling and Grammar", [
            item("Show Spelling and Grammar", sel("showGuessPanel:"), ":"),
            item("Check Document Now", sel("checkSpelling:"), ";"),
            .separator(),
            item("Check Spelling While Typing", sel("toggleContinuousSpellChecking:")),
            item("Check Grammar With Spelling", sel("toggleGrammarChecking:")),
            item("Correct Spelling Automatically", sel("toggleAutomaticSpellingCorrection:")),
        ])
        let substitutions = submenu("Substitutions", [
            item("Smart Quotes", sel("toggleAutomaticQuoteSubstitution:")),
            item("Smart Dashes", sel("toggleAutomaticDashSubstitution:")),
            item("Smart Links", sel("toggleAutomaticLinkDetection:")),
            item("Text Replacement", sel("toggleAutomaticTextReplacement:")),
        ])
        let transformations = submenu("Transformations", [
            item("Make Upper Case", sel("uppercaseWord:")),
            item("Make Lower Case", sel("lowercaseWord:")),
            item("Capitalize", sel("capitalizeWord:")),
        ])
        let speech = submenu("Speech", [
            item("Start Speaking", sel("startSpeaking:")),
            item("Stop Speaking", sel("stopSpeaking:")),
        ])
        return submenu("Edit", [
            item("Undo", sel("undo:"), "z"),
            item("Redo", sel("redo:"), "Z", [.command, .shift]),
            .separator(),
            item("Cut", sel("cut:"), "x"),
            item("Copy", sel("copy:"), "c"),
            item("Paste", sel("paste:"), "v"),
            item("Paste and Match Style", sel("pasteAsPlainText:"), "V", [.command, .option, .shift]),
            item("Delete", sel("delete:")),
            item("Select All", sel("selectAll:"), "a"),
            .separator(),
            find,
            spelling,
            substitutions,
            transformations,
            speech,
            .separator(),
            item("Start Dictation…", sel("startDictation:")),
            item("Emoji & Symbols", sel("orderFrontCharacterPalette:"), " ", [.command, .control]),
        ])
    }

    private static func formatMenu() -> NSMenuItem {
        let styles = submenu("Text Style", TextStyle.allCases.enumerated().map { i, s in
            item(s.label, #selector(TideTextView.tideStyle(_:)), "\(i + 1)", [.command, .option], tag: i)
        })
        var highlightItems = [item("None", #selector(TideTextView.tideHighlight(_:)), "0", [.control], tag: 0), NSMenuItem.separator()]
        for h in Highlight.allCases {
            let it = item(h.name, #selector(TideTextView.tideHighlight(_:)), "\(h.rawValue)", [.control], tag: h.rawValue)
            let swatch = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
                h.light.setFill()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
                NSColor.black.withAlphaComponent(0.15).setStroke()
                NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).stroke()
                return true
            }
            it.image = swatch
            highlightItems.append(it)
        }
        let highlight = submenu("Highlight", highlightItems)
        let lists = submenu("Lists", [
            item("Bulleted List", #selector(TideTextView.tideList(_:)), "7", [.command, .shift], tag: 1),
            item("Numbered List", #selector(TideTextView.tideList(_:)), "9", [.command, .shift], tag: 2),
            item("No List", #selector(TideTextView.tideList(_:)), tag: 0),
        ])
        let alignment = submenu("Alignment", [
            item("Align Left", #selector(TideTextView.tideAlign(_:)), "{", tag: NSTextAlignment.left.rawValue),
            item("Center", #selector(TideTextView.tideAlign(_:)), "|", tag: NSTextAlignment.center.rawValue),
            item("Align Right", #selector(TideTextView.tideAlign(_:)), "}", tag: NSTextAlignment.right.rawValue),
            item("Justify", #selector(TideTextView.tideAlign(_:)), "|", [.command, .option], tag: NSTextAlignment.justified.rawValue),
        ])
        let fontManager = NSFontManager.shared
        let font = submenu("Font", [
            item("Show Fonts", sel("orderFrontFontPanel:"), "t", target: fontManager),
            item("Bigger", sel("modifyFont:"), "+", tag: 3, target: fontManager),
            item("Smaller", sel("modifyFont:"), "-", tag: 4, target: fontManager),
            .separator(),
            item("Show Colors", sel("orderFrontColorPanel:"), "C", [.command, .shift]),
        ])
        return submenu("Format", [
            styles,
            .separator(),
            item("Bold", #selector(TideTextView.tideBold(_:)), "b"),
            item("Italic", #selector(TideTextView.tideItalic(_:)), "i"),
            item("Underline", #selector(TideTextView.tideUnderline(_:)), "u"),
            item("Strikethrough", #selector(TideTextView.tideStrikethrough(_:))),
            highlight,
            .separator(),
            lists,
            alignment,
            item("Increase Indent", #selector(TideTextView.tideIndent(_:)), "]"),
            item("Decrease Indent", #selector(TideTextView.tideOutdent(_:)), "["),
            .separator(),
            font,
        ])
    }

    private static func insertMenu() -> NSMenuItem {
        submenu("Insert", [
            item("Image…", #selector(TideTextView.tideInsertImage(_:)), "i", [.command, .option]),
            item("File…", #selector(TideTextView.tideInsertFile(_:))),
            item("Audio…", #selector(TideTextView.tideInsertAudio(_:))),
            .separator(),
            item("Equation…", #selector(TideTextView.tideInsertEquation(_:)), "e", [.command, .option]),
            item("Link…", #selector(TideTextView.tideInsertLink(_:)), "k"),
            item("Date", #selector(TideTextView.tideInsertDate(_:)), "D", [.command, .shift]),
        ])
    }

    private static func viewMenu() -> NSMenuItem {
        submenu("View", [
            item("Hide Panel", #selector(AppDelegate.togglePanel(_:)), "p", [.command, .option]),
            item("Panel on Left", #selector(AppDelegate.setPanelSide(_:)), tag: 0),
            item("Panel on Right", #selector(AppDelegate.setPanelSide(_:)), tag: 1),
            item("Show Word Count", #selector(AppDelegate.toggleWordCount(_:))),
            .separator(),
            item("Zoom In", #selector(AppDelegate.zoomIn(_:)), ">"),
            item("Zoom Out", #selector(AppDelegate.zoomOut(_:)), "<"),
            item("Actual Size", #selector(AppDelegate.zoomActual(_:)), "0"),
            .separator(),
            item("Enter Full Screen", sel("toggleFullScreen:"), "f", [.command, .control]),
        ])
    }

    private static func windowMenu() -> NSMenuItem {
        let it = submenu("Window", [
            item("Minimize", sel("performMiniaturize:"), "m"),
            item("Zoom", sel("performZoom:")),
            .separator(),
            item("Bring All to Front", sel("arrangeInFront:")),
        ])
        NSApp.windowsMenu = it.submenu
        return it
    }

    private static func helpMenu() -> NSMenuItem {
        let it = submenu("Help", [
            item("Tide Help", #selector(AppDelegate.showTideHelp(_:)), "?"),
            item("Keyboard Shortcuts", #selector(AppDelegate.showTideHelp(_:))),
        ])
        NSApp.helpMenu = it.submenu
        return it
    }
}

/// Fills File › Open Recent from NSDocumentController (built-in management needs a nib).
final class RecentDocumentsMenu: NSObject, NSMenuDelegate {
    static let shared = RecentDocumentsMenu()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let urls = NSDocumentController.shared.recentDocumentURLs
        for url in urls {
            let it = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
            it.target = self
            it.representedObject = url
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 16, height: 16)
            it.image = icon
            menu.addItem(it)
        }
        if !urls.isEmpty { menu.addItem(.separator()) }
        let clear = NSMenuItem(title: "Clear Menu", action: #selector(NSDocumentController.clearRecentDocuments(_:)), keyEquivalent: "")
        menu.addItem(clear)
    }

    @objc private func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error { NSApp.presentError(error) }
        }
    }
}
