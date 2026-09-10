import SwiftUI

// Liquid Glass when the toolchain and the OS have it (Xcode 26 SDK, macOS 26); a frosted material
// otherwise, so the project also builds with Xcode 16 and runs on macOS 14 and 15.
// Build with `-D TIDE_NO_GLASS` to force the fallback on a machine that has glass.

extension View {
    @ViewBuilder
    func tideGlass<S: Shape>(tint: Color? = nil, interactive: Bool = false, in shape: S) -> some View {
        #if compiler(>=6.2) && !TIDE_NO_GLASS
        if #available(macOS 26.0, *) {
            let glass: Glass = {
                var g = Glass.regular
                if let tint { g = g.tint(tint) }
                if interactive { g = g.interactive() }
                return g
            }()
            self.glassEffect(glass, in: shape)
        } else {
            frosted(tint: tint, in: shape)
        }
        #else
        frosted(tint: tint, in: shape)
        #endif
    }

    func frosted<S: Shape>(tint: Color?, in shape: S) -> some View {
        self
            .background(shape.fill(tint ?? Color.clear).background(shape.fill(.regularMaterial)))
            .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.14), radius: 14, y: 6)
    }
}

/// `GlassEffectContainer` where available; otherwise just the content.
struct GlassContainer<Content: View>: View {
    var spacing: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if compiler(>=6.2) && !TIDE_NO_GLASS
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}
