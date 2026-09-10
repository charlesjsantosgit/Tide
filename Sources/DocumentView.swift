import SwiftUI
import AppKit

struct EditorRepresentable: NSViewRepresentable {
    let editor: EditorController
    func makeNSView(context: Context) -> NSScrollView { editor.scrollView }
    func updateNSView(_ nsView: NSScrollView, context: Context) {}
}

struct DocumentView: View {
    @ObservedObject var editor: EditorController
    @AppStorage(SettingsKey.panelSide) private var panelSide = PanelSide.right.rawValue
    @AppStorage(SettingsKey.panelHidden) private var panelHidden = false
    @AppStorage(SettingsKey.showWordCount) private var showWordCount = true
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            LinearGradient(colors: Theme.backdropColors(dark: colorScheme == .dark), startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            EditorRepresentable(editor: editor)
                .padding(.top, editor.titlebarInset)
        }
        .overlay {
            if !panelHidden {
                GeometryReader { geo in
                    ZStack(alignment: panelSide == PanelSide.left.rawValue ? .leading : .trailing) {
                        Color.clear
                        FloatingPanel(editor: editor)
                            .frame(maxHeight: max(200, geo.size.height - editor.titlebarInset - 24))
                            .padding(.horizontal, 16)
                            .padding(.top, editor.titlebarInset)
                    }
                }
            }
        }
        .overlay(alignment: panelSide == PanelSide.left.rawValue ? .bottomTrailing : .bottomLeading) {
            if showWordCount {
                WordCountPill(editor: editor)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
            }
        }
        .sheet(item: $editor.equationRequest) { req in
            EquationSheet(editor: editor, request: req)
        }
        .sheet(item: $editor.linkRequest) { req in
            LinkSheet(editor: editor, request: req)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}

struct WordCountPill: View {
    @ObservedObject var editor: EditorController
    var body: some View {
        Text("\(editor.wordCount.formatted()) words · \(editor.characterCount.formatted()) characters")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .tideGlass(in: Capsule())
    }
}
