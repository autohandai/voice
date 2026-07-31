import SwiftUI

/// A sparse presentation surface for compact control clusters.
///
/// The macOS 26 branch is compile-time and runtime guarded because the package
/// currently supports Swift 5.9 and macOS 14. Older systems retain a native
/// material surface with the same layout and interaction behavior.
private struct ParityGlassSurfaceModifier: ViewModifier {
    let cornerRadius: CGFloat
    let tint: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    .regular.tint(tint),
                    in: .rect(cornerRadius: cornerRadius)
                )
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    private func fallback(_ content: Content) -> some View {
        content.background(
            .ultraThinMaterial,
            in: RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .background(
            tint,
            in: RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
        )
        .overlay {
            RoundedRectangle(
                cornerRadius: cornerRadius,
                style: .continuous
            )
            .stroke(.white.opacity(0.3), lineWidth: 1)
        }
    }
}

extension View {
    func parityGlassSurface(
        cornerRadius: CGFloat = 14,
        tint: Color = .clear
    ) -> some View {
        modifier(
            ParityGlassSurfaceModifier(
                cornerRadius: cornerRadius,
                tint: tint
            )
        )
    }

    func parityGlassCapsule(tint: Color = .clear) -> some View {
        parityGlassSurface(cornerRadius: 1_000, tint: tint)
    }
}
