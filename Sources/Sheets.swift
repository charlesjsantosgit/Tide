import SwiftUI
import AppKit

struct EquationSheet: View {
    @ObservedObject var editor: EditorController
    @State var request: EquationRequest
    @State private var preview: NSImage? = nil
    @State private var previewSize = CGSize.zero
    @State private var renderWork: DispatchWorkItem? = nil
    @State private var rendering = false
    @Environment(\.dismiss) private var dismiss

    private let examples = [
        "\\frac{a}{b}", "\\sqrt{x^2+y^2}", "\\sum_{i=1}^{n} x_i", "\\int_0^1 f(x)\\,dx",
        "x = \\frac{-b \\pm \\sqrt{b^2-4ac}}{2a}", "\\lim_{x \\to \\infty}", "\\alpha \\beta \\gamma \\pi",
        "\\begin{pmatrix} a & b \\\\ c & d \\end{pmatrix}", "e^{i\\pi} + 1 = 0",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(request.replaceRange == nil ? "Insert Equation" : "Edit Equation").font(.headline)
            TextEditor(text: $request.source)
                .font(.system(size: 13, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(height: 84)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1)))
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.04))
                if let preview {
                    Image(nsImage: preview)
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: min(previewSize.width, 400), height: min(previewSize.height, 88))
                        .foregroundStyle(.primary)
                } else {
                    Text(request.source.trimmingCharacters(in: .whitespaces).isEmpty ? "Type LaTeX to see a preview" : (rendering ? "Rendering…" : "Couldn't render that"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 100)
            Picker("", selection: $request.display) {
                Text("On its own line").tag(true)
                Text("Inline with text").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(examples, id: \.self) { ex in
                        Button(ex) {
                            request.source += (request.source.isEmpty ? "" : " ") + ex
                        }
                        .font(.system(size: 11, design: .monospaced))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            HStack {
                Text("LaTeX: \\frac, \\sqrt, ^, _, \\sum, \\int, Greek letters, matrices…")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(request.replaceRange == nil ? "Insert" : "Update") {
                    editor.commitEquation(request)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(request.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { schedulePreview() }
        .onChange(of: request.source) { schedulePreview() }
        .onChange(of: request.display) { schedulePreview() }
    }

    private func schedulePreview() {
        renderWork?.cancel()
        let source = request.source
        let display = request.display
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { preview = nil; return }
        rendering = true
        let work = DispatchWorkItem {
            EquationRenderer.shared.render(latex: source, display: display, fontSize: 22) { result in
                guard source == request.source else { return }
                rendering = false
                preview = result?.image
                previewSize = result?.size ?? .zero
            }
        }
        renderWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

struct LinkSheet: View {
    @ObservedObject var editor: EditorController
    @State var request: LinkRequest
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Link").font(.headline)
            TextField("https://example.com", text: $request.url).textFieldStyle(.roundedBorder)
            TextField("Text to show", text: $request.text).textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add") {
                    editor.commitLink(request)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(request.url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}
