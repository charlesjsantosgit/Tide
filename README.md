# Tide

A small, glassy word processor for macOS Tahoe. Think Essayist's calm page and floating
capsule, Word's file format, and nothing else in the way.

![The Tide Manual with the panel open](docs/tide-panel-expanded.png)

Every document is a real **.docx**. Tide writes Word files itself (Apple's built-in writer
drops highlights, pictures and links), so headings, highlights, lists, links, pictures and
equations survive the trip to Word, Pages and Google Docs — and back.

## The panel

The oval on the side of the window is the whole toolbox. Hover over it and it expands;
move away and it folds back into a pill of status icons. Pin it open with the pin at the
bottom, or switch it to click-to-open in Settings › Panel.

| collapsed | dark mode |
|---|---|
| ![](docs/tide-panel-collapsed.png) | ![](docs/tide-dark.png) |

- **Style** — Title, Heading, Subheading, Body (exported as Word's Title / Heading 1 / Heading 2)
- **Format** — bold, italic, underline, strikethrough
- **Highlight** — five colours tuned for blue glass: Sky, Mint, Butter, Lilac, Blush
- **Lists** — bulleted, numbered, indent/outdent (Tab and Shift-Tab nest items; numbers renumber themselves)
- **Align** — left, centre, right, justify
- **Insert** — image, file, equation, audio, link
- **Settings** — also in the menu bar (`⌘,`)

## Equations

Insert › Equation takes LaTeX and renders it with the system's math fonts:
`\frac{a}{b}`, `\sqrt{x}`, `x^2`, `a_i`, `\sum_{i=1}^{n}`, `\int_0^1`, Greek letters,
`\left( … \right)`, `\begin{pmatrix} … \end{pmatrix}`, `\begin{cases} … \end{cases}` and the
usual operators. Equations can sit inline or on their own line; double-click one to edit it.
In .docx they are pictures with the LaTeX kept in the alt text, so Tide can edit them again
after a round trip. In Markdown they become `$…$` / `$$…$$`.

![Equation editor](docs/tide-equation.png)

## Files

| | Open | Save / Save As | Export |
|---|---|---|---|
| Word (.docx) | ✓ | ✓ (native) | ✓ |
| Rich Text (.rtf, .rtfd) | ✓ | ✓ | ✓ |
| Plain text (.txt) | ✓ | ✓ | ✓ |
| Markdown (.md) | ✓ | ✓ | ✓ |
| Web page (.html) | ✓ | ✓ | ✓ (self-contained, pictures inlined) |
| PDF | | | ✓ (also Print) |

**File › Import…** inserts another document at the cursor. Markdown understands
Obsidian-style `==highlight==`, `$math$` and YAML front matter.

Audio and other files appear as chips (click an audio chip to play it, a file chip to open
it). In .docx they become links to the original file; Tide turns them back into chips when
it opens the file again.

## Settings

Font family, body size, line spacing, page width, paper (always light or match appearance),
paper size (US Letter / A4), zoom, spelling and autocorrect, smart quotes, panel side and
expand behaviour, word count.

![Settings](docs/tide-settings.png)

## Shortcuts

| | |
|---|---|
| `⌘B` `⌘I` `⌘U` | bold, italic, underline |
| `⌃1` – `⌃5` / `⌃0` | highlight Sky … Blush / none |
| `⌥⌘1` – `⌥⌘4` | Title, Heading, Subheading, Body |
| `⇧⌘7` / `⇧⌘9` | bulleted / numbered list |
| `⌘]` / `⌘[` | indent / outdent |
| `⌥⌘E` | equation |
| `⌘K` | link |
| `⌥⌘I` | image |
| `⇧⌘I` | import |
| `⌥⌘P` | show / hide the panel |
| `⌘>` `⌘<` `⌘0` | zoom |

## Updates and distribution

Tide updates itself. It checks [GitHub Releases](https://github.com/charlesjsantosgit/Tide/releases)
about once a day (and on **Tide › Check for Updates…**), shows the release notes, downloads the zip,
verifies it is Tide, swaps the bundle on disk and relaunches. Settings › Updates has the switch and
the feed URL.

```
./build.sh --package          # -> build.nosync/dist/Tide-<version>.zip + release.json
python3 tools/serve.py        # local download page at http://localhost:8787/ (also on the LAN)
tools/release.sh 1.0.1 "…"    # bump VERSION, build+test+package, commit, tag, push, GitHub release
tools/test-update.sh          # end-to-end proof: a copy of the app updates itself from serve.py
```

`tools/serve.py` serves a download page with the full `.app` (zipped), and a feed at
`/releases/latest` in the same JSON shape GitHub uses, so you can point the app at your own Mac
to try an update before publishing it:

```
defaults write com.charlessantos.tide updateFeedURL http://localhost:8787/releases/latest
```

The binary has matching switches: `--version`, `--update-check [feed]`, `--update-dryrun [feed]`
(download and verify only) and `--update-now [feed]` (install and relaunch).

## Build

```
./build.sh                 # -> build.nosync/Tide.app
./build.sh --install       # also copies to ~/Applications and registers it for .docx
./build.sh --test          # runs the self-test (formatting, lists, every file format)
./build.sh --shots         # regenerates the screenshots in docs/
```

No Xcode project — `swiftc` straight to an app bundle, ad-hoc signed. Build output lives in `build.nosync/` so iCloud never evicts it. The build needs the macOS 26 SDK (Xcode 26 or its Command Line Tools); on a Mac with an older toolchain `build.sh` first runs `tools/setup-toolchain.sh`, which selects an installed Xcode 26, or installs the newest Command Line Tools through Software Update, or Xcode from the App Store (it asks for your password). If none of that is possible (macOS older than 15.6) it still builds, with a frosted panel instead of Liquid Glass. The app runs on macOS 14 and later. `UNIVERSAL=1 ./build.sh` builds an arm64 + x86_64 binary; `MIN_OS`, `ARCH`, `EXTRA_SWIFTFLAGS` and `NO_TOOLCHAIN_UPDATE=1` are honoured.

Hidden switches on the binary: `--selftest`, `--snapshot <dir>` (renders the sample
document off-screen and captures the UI), `--dump <file>` (prints how a document imports),
plus the update switches above. `VERSION` holds the version number; `CHANGELOG.md` feeds the
release notes.

## How it is put together

- **AppKit document architecture** (`TideDocument`, `NSDocumentController`) for the menu bar,
  Open/Save/Save As/Duplicate/Rename/Revert, autosave and versions. The menu bar is built in code.
- **TextKit 1** `NSTextView` inside a page host that centres the paper. List markers are real
  text (`\t•\t`), the paragraph style carries the `NSTextList`; `EditorController` owns every
  formatting operation and the Return/Delete/Tab behaviour inside lists.
- **SwiftUI on top**: the document view, the Liquid Glass panel (`glassEffect` in a
  `GlassEffectContainer`), the equation and link sheets, Settings and Help.
- **Own .docx reader and writer** (`DocxWriter`, `DocxReader`, `Zip`): document, styles,
  numbering, media, hyperlinks, core properties. Reading tolerates Word-authored files
  (tables flatten to paragraphs; headers, footers, footnotes and comments are skipped).
- **Equations**: a LaTeX subset → MathML, rendered by an off-screen `WKWebView` at 2x and
  turned into an alpha mask that the text view tints with the text colour, so equations
  follow dark paper.
- **Attachments**: `ImageCell`, `EquationCell` and `FileChipCell` draw pictures, equations and
  chips. AppKit swaps audio/video attachments over to its own media view and discards custom
  cells, so chips use a `ChipAttachment` subclass that keeps its cell.

## Known limits

- .docx round trip covers what Tide can make; Word features Tide does not model (tables,
  headers/footers, footnotes, comments, tracked changes, text boxes) are flattened or dropped.
- Equations are pictures in .docx (with the LaTeX in alt text), not Word's native equations.
- Audio and file chips export as links, not embedded objects.
