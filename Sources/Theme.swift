import AppKit
import SwiftUI

enum Theme {
    /// Tide blue: caret, links, active controls, glass tint.
    static let tideBlue = NSColor(srgbRed: 0.20, green: 0.48, blue: 0.97, alpha: 1)
    static var accent: Color { Color(nsColor: tideBlue) }
    static var panelTint: Color { accent.opacity(0.16) }

    static func backdropColors(dark: Bool) -> [Color] {
        dark
            ? [Color(red: 0.05, green: 0.09, blue: 0.19), Color(red: 0.07, green: 0.11, blue: 0.21), Color(red: 0.09, green: 0.12, blue: 0.20)]
            : [Color(red: 0.83, green: 0.90, blue: 1.00), Color(red: 0.90, green: 0.95, blue: 1.00), Color(red: 0.95, green: 0.97, blue: 1.00)]
    }

    static let paperLight = NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1)
    static let paperDark = NSColor(srgbRed: 0.12, green: 0.14, blue: 0.19, alpha: 1)
    /// Paper colour that follows the effective appearance (used when paper = "auto").
    static let paperDynamic = NSColor(name: "TidePaper") { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? paperDark : paperLight
    }
}
