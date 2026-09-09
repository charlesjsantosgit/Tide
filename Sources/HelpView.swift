import SwiftUI

struct HelpView: View {
    private let shortcuts: [(String, String)] = [
        ("⌘N / ⌘O / ⌘S", "New, Open, Save"),
        ("⇧⌘S", "Save As…"),
        ("⇧⌘I", "Import a file into the document"),
        ("⌘B / ⌘I / ⌘U", "Bold, Italic, Underline"),
        ("⌃1 – ⌃5", "Highlight: Sky, Mint, Butter, Lilac, Blush"),
        ("⌃0", "Remove highlight"),
        ("⌥⌘1 – ⌥⌘4", "Title, Heading, Subheading, Body"),
        ("⇧⌘7 / ⇧⌘9", "Bulleted / numbered list"),
        ("⌘] / ⌘[", "Indent / outdent (also nests lists)"),
        ("⌥⌘E", "Insert equation (LaTeX)"),
        ("⌘K", "Add link"),
        ("⌥⌘P", "Show / hide the panel"),
        ("⌘> / ⌘< / ⌘0", "Zoom in / out / actual size"),
        ("⌘F", "Find"),
        ("⌘,", "Settings"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Tide Help").font(.title.bold())
                Group {
                    Text("Writing").font(.headline)
                    Text("Tide is a small word processor. Every document is a real Word file (.docx), so what you write opens in Word, Pages and Google Docs with its headings, highlights, lists, links and pictures intact. Save As… also offers Rich Text, Plain Text, Markdown and HTML, and Export makes PDFs.")
                }
                Group {
                    Text("The panel").font(.headline)
                    Text("The oval on the side of the window expands when you hover over it (or click it, if you prefer — see Settings › Panel). It holds text styles, bold/italic/underline, five highlight colours, lists, alignment, and inserts for images, files, audio, equations and links. Pin it open with the pin at the bottom.")
                }
                Group {
                    Text("Lists").font(.headline)
                    Text("Press Return to add an item, Return on an empty item to leave the list, Tab or Shift-Tab to nest and un-nest. Numbered lists renumber themselves.")
                }
                Group {
                    Text("Equations").font(.headline)
                    Text("Insert › Equation takes LaTeX: \\frac{a}{b}, \\sqrt{x}, x^2, a_i, \\sum_{i=1}^n, \\int_0^1, Greek letters, \\left( \\right), matrices and cases. Double-click an equation to edit it. Equations are stored as pictures in .docx with their source kept as alt text, so they survive a round trip through Tide.")
                }
                Group {
                    Text("Audio and files").font(.headline)
                    Text("Audio and other files appear as chips. Click an audio chip to play it, click a file chip to open it. In .docx they become links to the original file.")
                }
                Group {
                    Text("Keyboard shortcuts").font(.headline)
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(shortcuts, id: \.0) { pair in
                            HStack(alignment: .top) {
                                Text(pair.0).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 150, alignment: .leading)
                                Text(pair.1).font(.system(size: 12))
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 520, height: 560)
    }
}
