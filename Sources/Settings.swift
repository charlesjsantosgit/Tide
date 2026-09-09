import AppKit
import SwiftUI

enum SettingsKey {
    static let fontFamily = "fontFamily"
    static let bodySize = "bodySize"
    static let lineSpacing = "lineSpacing"
    static let pageWidth = "pageWidth"
    static let paper = "paper"
    static let spellCheck = "spellCheck"
    static let autocorrect = "autocorrect"
    static let smartQuotes = "smartQuotes"
    static let panelSide = "panelSide"
    static let panelExpand = "panelExpand"
    static let panelPinned = "panelPinned"
    static let panelHidden = "panelHidden"
    static let showWordCount = "showWordCount"
    static let paperSize = "paperSize"
    static let zoom = "zoom"
}

enum PageWidthOption: String, CaseIterable, Identifiable {
    case narrow, standard, wide
    var id: String { rawValue }
    var label: String {
        switch self { case .narrow: return "Narrow"; case .standard: return "Standard"; case .wide: return "Wide" }
    }
    var points: CGFloat {
        switch self { case .narrow: return 560; case .standard: return 680; case .wide: return 840 }
    }
}

enum PaperOption: String, CaseIterable, Identifiable {
    case light, auto
    var id: String { rawValue }
}

enum PanelSide: String, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
}

enum PanelExpandMode: String, CaseIterable, Identifiable {
    case hover, click
    var id: String { rawValue }
}

enum PaperSize: String, CaseIterable, Identifiable {
    case letter, a4
    var id: String { rawValue }
    var label: String { self == .letter ? "US Letter" : "A4" }
    var size: NSSize { self == .letter ? NSSize(width: 612, height: 792) : NSSize(width: 595.276, height: 841.89) }
    /// Page size in twips (1/20 pt) for Word.
    var twips: (w: Int, h: Int) { self == .letter ? (12240, 15840) : (11906, 16838) }
}

enum Settings {
    static let systemFamily = "System"
    static let fontFamilies = ["System", "Helvetica Neue", "Avenir Next", "Georgia", "Times New Roman", "Palatino", "Charter", "Baskerville", "Menlo"]

    private static var d: UserDefaults { .standard }

    static func registerDefaults() {
        d.register(defaults: [
            SettingsKey.fontFamily: "Helvetica Neue",
            SettingsKey.bodySize: 12.0,
            SettingsKey.lineSpacing: 1.15,
            SettingsKey.pageWidth: PageWidthOption.standard.rawValue,
            SettingsKey.paper: PaperOption.light.rawValue,
            SettingsKey.spellCheck: true,
            SettingsKey.autocorrect: true,
            SettingsKey.smartQuotes: true,
            SettingsKey.panelSide: PanelSide.right.rawValue,
            SettingsKey.panelExpand: PanelExpandMode.hover.rawValue,
            SettingsKey.panelPinned: false,
            SettingsKey.panelHidden: false,
            SettingsKey.showWordCount: true,
            SettingsKey.paperSize: PaperSize.letter.rawValue,
            SettingsKey.zoom: 1.25,
            Updater.autoKey: true,
            Updater.feedKey: Updater.defaultFeed,
        ])
    }

    static var fontFamily: String {
        get { d.string(forKey: SettingsKey.fontFamily) ?? "Helvetica Neue" }
        set { d.set(newValue, forKey: SettingsKey.fontFamily) }
    }
    static var bodySize: CGFloat {
        get { let v = d.double(forKey: SettingsKey.bodySize); return v > 0 ? CGFloat(v) : 12 }
        set { d.set(Double(newValue), forKey: SettingsKey.bodySize) }
    }
    static var lineSpacing: CGFloat {
        get { let v = d.double(forKey: SettingsKey.lineSpacing); return v > 0 ? CGFloat(v) : 1.15 }
        set { d.set(Double(newValue), forKey: SettingsKey.lineSpacing) }
    }
    static var pageWidth: PageWidthOption {
        get { PageWidthOption(rawValue: d.string(forKey: SettingsKey.pageWidth) ?? "") ?? .standard }
        set { d.set(newValue.rawValue, forKey: SettingsKey.pageWidth) }
    }
    static var paper: PaperOption {
        get { PaperOption(rawValue: d.string(forKey: SettingsKey.paper) ?? "") ?? .light }
        set { d.set(newValue.rawValue, forKey: SettingsKey.paper) }
    }
    static var spellCheck: Bool { get { d.bool(forKey: SettingsKey.spellCheck) } set { d.set(newValue, forKey: SettingsKey.spellCheck) } }
    static var autocorrect: Bool { get { d.bool(forKey: SettingsKey.autocorrect) } set { d.set(newValue, forKey: SettingsKey.autocorrect) } }
    static var smartQuotes: Bool { get { d.bool(forKey: SettingsKey.smartQuotes) } set { d.set(newValue, forKey: SettingsKey.smartQuotes) } }
    static var panelSide: PanelSide {
        get { PanelSide(rawValue: d.string(forKey: SettingsKey.panelSide) ?? "") ?? .right }
        set { d.set(newValue.rawValue, forKey: SettingsKey.panelSide) }
    }
    static var panelExpand: PanelExpandMode {
        get { PanelExpandMode(rawValue: d.string(forKey: SettingsKey.panelExpand) ?? "") ?? .hover }
        set { d.set(newValue.rawValue, forKey: SettingsKey.panelExpand) }
    }
    static var panelHidden: Bool { get { d.bool(forKey: SettingsKey.panelHidden) } set { d.set(newValue, forKey: SettingsKey.panelHidden) } }
    static var showWordCount: Bool { get { d.bool(forKey: SettingsKey.showWordCount) } set { d.set(newValue, forKey: SettingsKey.showWordCount) } }
    static var paperSize: PaperSize {
        get { PaperSize(rawValue: d.string(forKey: SettingsKey.paperSize) ?? "") ?? .letter }
        set { d.set(newValue.rawValue, forKey: SettingsKey.paperSize) }
    }
    static var zoom: CGFloat {
        get { let v = d.double(forKey: SettingsKey.zoom); return v > 0 ? CGFloat(v) : 1.25 }
        set { d.set(Double(newValue), forKey: SettingsKey.zoom) }
    }
}

// MARK: - Settings window content

struct SettingsView: View {
    @AppStorage(SettingsKey.fontFamily) private var fontFamily = "Helvetica Neue"
    @AppStorage(SettingsKey.bodySize) private var bodySize = 12.0
    @AppStorage(SettingsKey.lineSpacing) private var lineSpacing = 1.15
    @AppStorage(SettingsKey.pageWidth) private var pageWidth = PageWidthOption.standard.rawValue
    @AppStorage(SettingsKey.paper) private var paper = PaperOption.light.rawValue
    @AppStorage(SettingsKey.paperSize) private var paperSize = PaperSize.letter.rawValue
    @AppStorage(SettingsKey.zoom) private var zoom = 1.25
    @AppStorage(SettingsKey.spellCheck) private var spellCheck = true
    @AppStorage(SettingsKey.autocorrect) private var autocorrect = true
    @AppStorage(SettingsKey.smartQuotes) private var smartQuotes = true
    @AppStorage(SettingsKey.panelSide) private var panelSide = PanelSide.right.rawValue
    @AppStorage(SettingsKey.panelExpand) private var panelExpand = PanelExpandMode.hover.rawValue
    @AppStorage(SettingsKey.showWordCount) private var showWordCount = true
    @AppStorage(SettingsKey.panelHidden) private var panelHidden = false
    @AppStorage(Updater.autoKey) private var autoUpdate = true
    @AppStorage(Updater.feedKey) private var updateFeed = Updater.defaultFeed

    var body: some View {
        TabView {
            Form {
                Section("Text") {
                    Picker("Font", selection: $fontFamily) {
                        ForEach(Settings.fontFamilies, id: \.self) { family in
                            Text(family).tag(family)
                        }
                    }
                    Stepper("Body size: \(Int(bodySize)) pt", value: $bodySize, in: 10...18, step: 1)
                    Picker("Line spacing", selection: $lineSpacing) {
                        Text("Single").tag(1.0)
                        Text("1.15").tag(1.15)
                        Text("1.5").tag(1.5)
                        Text("Double").tag(2.0)
                    }
                }
                Section("Page") {
                    Picker("Page width", selection: $pageWidth) {
                        ForEach(PageWidthOption.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Paper", selection: $paper) {
                        Text("Always light").tag(PaperOption.light.rawValue)
                        Text("Match appearance").tag(PaperOption.auto.rawValue)
                    }
                    Picker("Paper size", selection: $paperSize) {
                        ForEach(PaperSize.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                    Picker("Zoom", selection: $zoom) {
                        Text("100%").tag(1.0)
                        Text("125%").tag(1.25)
                        Text("150%").tag(1.5)
                        Text("175%").tag(1.75)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "textformat") }

            Form {
                Section("While typing") {
                    Toggle("Check spelling", isOn: $spellCheck)
                    Toggle("Correct spelling automatically", isOn: $autocorrect)
                    Toggle("Smart quotes and dashes", isOn: $smartQuotes)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Editing", systemImage: "pencil") }

            Form {
                Section("Floating panel") {
                    Picker("Position", selection: $panelSide) {
                        Text("Left").tag(PanelSide.left.rawValue)
                        Text("Right").tag(PanelSide.right.rawValue)
                    }
                    .pickerStyle(.segmented)
                    Picker("Expand", selection: $panelExpand) {
                        Text("When hovered").tag(PanelExpandMode.hover.rawValue)
                        Text("When clicked").tag(PanelExpandMode.click.rawValue)
                    }
                    Toggle("Show panel", isOn: Binding(get: { !panelHidden }, set: { panelHidden = !$0 }))
                }
                Section("Status") {
                    Toggle("Show word count", isOn: $showWordCount)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Panel", systemImage: "sidebar.trailing") }

            Form {
                Section("Updates") {
                    LabeledContent("Installed version", value: Updater.currentVersion)
                    Toggle("Check for updates automatically", isOn: $autoUpdate)
                    HStack {
                        Text("Tide checks GitHub Releases about once a day.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Check Now") { Updater.shared.check(userInitiated: true) }
                    }
                }
                Section("Update feed") {
                    TextField("Feed URL", text: $updateFeed)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                    HStack {
                        Text("Point this at tools/serve.py to test an update from your own Mac.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Use GitHub") { updateFeed = Updater.defaultFeed }
                            .disabled(updateFeed == Updater.defaultFeed)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Updates", systemImage: "arrow.down.circle") }
        }
        .frame(width: 500, height: 420)
    }
}
