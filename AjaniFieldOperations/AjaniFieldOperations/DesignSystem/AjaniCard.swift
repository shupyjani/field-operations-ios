import SwiftUI

struct AjaniCardModifier: ViewModifier {
    var padding: CGFloat = AjaniTheme.Spacing.l

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AjaniTheme.Radius.card, style: .continuous)
                    .fill(AjaniTheme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AjaniTheme.Radius.card, style: .continuous)
                    .strokeBorder(AjaniTheme.Palette.separator, lineWidth: 1)
            )
    }
}

extension View {
    func ajaniCard(padding: CGFloat = AjaniTheme.Spacing.l) -> some View {
        modifier(AjaniCardModifier(padding: padding))
    }

    /// Applies the warm ivory canvas behind a scrolling screen.
    func ajaniCanvas() -> some View {
        background(AjaniTheme.Palette.canvas)
    }
}
