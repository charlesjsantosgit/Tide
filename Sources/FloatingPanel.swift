import SwiftUI
import AppKit

/// The Essayist-style capsule docked to the side of the window. Collapsed it is a thin oval of
/// status icons; hover (or click, per Settings) morphs it into the full formatting panel.
struct FloatingPanel: View {
    @ObservedObject var editor: EditorController
    @AppStorage(SettingsKey.panelExpand) private var expandMode = PanelExpandMode.hover.rawValue
    @AppStorage(SettingsKey.panelPinned) private var pinned = false
    @State private var hovering = false
    @State private var clickedOpen = false
    @State private var collapseWork: DispatchWorkItem? = nil

    private var expanded: Bool {
        if editor.forceExpanded || pinned { return true }
        return expandMode == PanelExpandMode.click.rawValue ? clickedOpen : hovering
    }

    var body: some View {
        GlassContainer(spacing: 20) {
            VStack(spacing: 0) {
                if expanded {
                    ViewThatFits(in: .vertical) {
                        expandedContent
                        ScrollView(.vertical, showsIndicators: false) { expandedContent }
                    }
                    .transition(.opacity)
                } else {
                    CollapsedPanel(editor: editor) {
                        if expandMode == PanelExpandMode.click.rawValue { clickedOpen = true }
                    }
                    .transition(.opacity)
                }
            }
            .frame(width: expanded ? 244 : 46)
            .tideGlass(tint: Theme.panelTint, interactive: true, in: RoundedRectangle(cornerRadius: 23, style: .continuous))
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.84), value: expanded)
        .onHover { inside in
            if inside {
                collapseWork?.cancel()
                collapseWork = nil
                hovering = true
            } else {
                let clickMode = expandMode == PanelExpandMode.click.rawValue
                let work = DispatchWorkItem {
                    hovering = false
                    if clickMode { clickedOpen = false }
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + (clickMode ? 1.2 : 0.4), execute: work)
            }
        }
    }

    private var expandedContent: some View {
        ExpandedPanel(editor: editor, pinned: $pinned) {
            clickedOpen = false
            hovering = false
        }
    }
}

struct CollapsedPanel: View {
    @ObservedObject var editor: EditorController
    var tap: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            icon("textformat.size", active: editor.state.style != .body)
            icon("bold", active: editor.state.bold)
            icon("italic", active: editor.state.italic)
            icon("underline", active: editor.state.underline)
            highlightDot
            icon("list.bullet", active: editor.state.list != nil)
            icon("photo", active: false)
            icon("gearshape", active: false)
        }
        .padding(.vertical, 16)
        .frame(width: 46)
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
    }

    private func icon(_ name: String, active: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? Theme.accent : Color.primary.opacity(0.7))
            .frame(width: 22, height: 18)
    }

    private var highlightDot: some View {
        Circle()
            .fill(editor.state.highlight.map { Color(nsColor: $0.light) } ?? Color.primary.opacity(0.14))
            .frame(width: 12, height: 12)
            .overlay(Circle().stroke(Color.primary.opacity(0.22), lineWidth: 1))
            .frame(height: 18)
    }
}

struct ExpandedPanel: View {
    @ObservedObject var editor: EditorController
    @Binding var pinned: Bool
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            section("Style") {
                VStack(spacing: 2) {
                    ForEach(TextStyle.allCases) { style in
                        StyleRow(style: style, active: editor.state.style == style) {
                            editor.applyTextStyle(style)
                            editor.focus()
                        }
                    }
                }
            }
            section("Format") {
                HStack(spacing: 6) {
                    PanelIconButton("bold", tip: "Bold (⌘B)", active: editor.state.bold) { editor.toggleBold(); editor.focus() }
                    PanelIconButton("italic", tip: "Italic (⌘I)", active: editor.state.italic) { editor.toggleItalic(); editor.focus() }
                    PanelIconButton("underline", tip: "Underline (⌘U)", active: editor.state.underline) { editor.toggleUnderline(); editor.focus() }
                    PanelIconButton("strikethrough", tip: "Strikethrough", active: editor.state.strike) { editor.toggleStrikethrough(); editor.focus() }
                    Spacer(minLength: 0)
                }
            }
            section("Highlight") {
                HStack(spacing: 9) {
                    ForEach(Highlight.allCases) { h in
                        Swatch(highlight: h, active: editor.state.highlight == h) {
                            editor.applyHighlight(h)
                            editor.focus()
                        }
                    }
                    Button {
                        editor.applyHighlight(nil)
                        editor.focus()
                    } label: {
                        Image(systemName: "circle.slash")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Remove highlight")
                    Spacer(minLength: 0)
                }
            }
            section("Lists") {
                HStack(spacing: 6) {
                    PanelIconButton("list.bullet", tip: "Bulleted list (⇧⌘7)", active: editor.state.list == .bullet) { editor.toggleList(.bullet); editor.focus() }
                    PanelIconButton("list.number", tip: "Numbered list (⇧⌘9)", active: editor.state.list == .numbered) { editor.toggleList(.numbered); editor.focus() }
                    Divider().frame(height: 16).padding(.horizontal, 2)
                    PanelIconButton("decrease.indent", tip: "Outdent (⌘[)", active: false) { editor.changeIndent(by: -1); editor.focus() }
                    PanelIconButton("increase.indent", tip: "Indent (⌘])", active: false) { editor.changeIndent(by: 1); editor.focus() }
                    Spacer(minLength: 0)
                }
            }
            section("Align") {
                HStack(spacing: 6) {
                    PanelIconButton("text.alignleft", tip: "Align left", active: editor.state.alignment == .left || editor.state.alignment == .natural) { editor.setAlignment(.left); editor.focus() }
                    PanelIconButton("text.aligncenter", tip: "Center", active: editor.state.alignment == .center) { editor.setAlignment(.center); editor.focus() }
                    PanelIconButton("text.alignright", tip: "Align right", active: editor.state.alignment == .right) { editor.setAlignment(.right); editor.focus() }
                    PanelIconButton("text.justify", tip: "Justify", active: editor.state.alignment == .justified) { editor.setAlignment(.justified); editor.focus() }
                    Spacer(minLength: 0)
                }
            }
            section("Insert") {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                    InsertButton("Image", "photo") { editor.insertImageFromPanel() }
                    InsertButton("File", "paperclip") { editor.insertFileFromPanel() }
                    InsertButton("Equation", "x.squareroot") { editor.requestEquation() }
                    InsertButton("Audio", "waveform") { editor.insertAudioFromPanel() }
                    InsertButton("Link", "link") { editor.requestLink() }
                }
            }
            Divider().opacity(0.6)
            HStack {
                Button {
                    NSApp.sendAction(#selector(AppDelegate.showSettings(_:)), to: nil, from: nil)
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tide settings (⌘,)")
                Spacer()
                Button {
                    pinned.toggle()
                    if !pinned { close() }
                } label: {
                    Image(systemName: pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(pinned ? Theme.accent : Color.secondary)
                        .frame(width: 22, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(pinned ? "Let the panel collapse" : "Keep the panel open")
            }
        }
        .padding(14)
        .frame(width: 244)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

struct PanelIconButton: View {
    let symbol: String
    let tip: String
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    init(_ symbol: String, tip: String, active: Bool, action: @escaping () -> Void) {
        self.symbol = symbol
        self.tip = tip
        self.active = active
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 32, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(active ? Theme.accent.opacity(0.22) : (hover ? Color.primary.opacity(0.08) : Color.clear))
                )
                .foregroundStyle(active ? Theme.accent : Color.primary.opacity(0.85))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(tip)
    }
}

struct StyleRow: View {
    let style: TextStyle
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    private var font: Font {
        switch style {
        case .title: return .system(size: 15, weight: .bold)
        case .heading: return .system(size: 13, weight: .bold)
        case .subheading: return .system(size: 12, weight: .semibold)
        case .body: return .system(size: 12, weight: .regular)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack {
                Text(style.label).font(font)
                Spacer()
                if active {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(active ? Theme.accent.opacity(0.18) : (hover ? Color.primary.opacity(0.07) : Color.clear))
            )
            .foregroundStyle(active ? Theme.accent : Color.primary.opacity(0.9))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct Swatch: View {
    let highlight: Highlight
    let active: Bool
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: highlight.light))
                .frame(width: 20, height: 20)
                .overlay(Circle().stroke(active ? Theme.accent : Color.black.opacity(0.15), lineWidth: active ? 2 : 1))
                .scaleEffect(hover ? 1.12 : 1)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(.easeOut(duration: 0.12), value: hover)
        .help(highlight.name)
    }
}

struct InsertButton: View {
    let title: String
    let symbol: String
    let action: () -> Void
    @State private var hover = false

    init(_ title: String, _ symbol: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = symbol
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold)).frame(width: 14)
                Text(title).font(.system(size: 11.5, weight: .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(hover ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.06)))
            .foregroundStyle(hover ? Theme.accent : Color.primary.opacity(0.85))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
