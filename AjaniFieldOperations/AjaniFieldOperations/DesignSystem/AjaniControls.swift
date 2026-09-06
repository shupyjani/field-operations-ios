import SwiftUI

struct AjaniPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(AjaniTheme.Palette.surface)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AjaniTheme.Layout.minimumTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AjaniTheme.Radius.inner, style: .continuous)
                    .fill(AjaniTheme.Palette.primary)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.98)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AjaniTheme.Spacing.xs) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(AjaniTheme.Palette.textPrimary)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct AjaniProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AjaniTheme.Palette.primarySoft)
                Capsule()
                    .fill(AjaniTheme.Palette.primary)
                    .frame(width: proxy.size.width * min(max(fraction, 0), 1))
            }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

struct EmptyStateView: View {
    let symbolName: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: AjaniTheme.Spacing.m) {
            Image(systemName: symbolName)
                // A text style rather than a fixed point size, so the icon grows
                // with the surrounding copy.
                .font(.largeTitle)
                .foregroundStyle(AjaniTheme.Palette.primary)
            Text(title)
                .font(.headline)
                .foregroundStyle(AjaniTheme.Palette.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AjaniTheme.Palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AjaniTheme.Spacing.xxl)
        .padding(.horizontal, AjaniTheme.Spacing.l)
        .accessibilityElement(children: .combine)
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    var symbolName: String?

    /// The icon gutter scales with the text, so glyphs never overflow it.
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 22

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AjaniTheme.Spacing.m) {
            if let symbolName {
                Image(systemName: symbolName)
                    .font(.subheadline)
                    .foregroundStyle(AjaniTheme.Palette.primary)
                    .frame(width: iconWidth, alignment: .leading)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.footnote)
                    .foregroundStyle(AjaniTheme.Palette.textSecondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(AjaniTheme.Palette.textPrimary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
