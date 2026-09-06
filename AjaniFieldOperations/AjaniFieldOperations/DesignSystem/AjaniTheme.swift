import SwiftUI
import UIKit

/// Design tokens for the Ajani field-operations interface.
enum AjaniTheme {}

extension AjaniTheme {
    enum Palette {
        /// Warm ivory canvas behind every screen.
        static let canvas = adaptive(
            light: Color(red: 0.980, green: 0.965, blue: 0.937),
            dark: Color(red: 0.074, green: 0.071, blue: 0.063)
        )

        /// Raised card surface.
        static let surface = adaptive(
            light: Color(red: 1.000, green: 0.992, blue: 0.976),
            dark: Color(red: 0.118, green: 0.110, blue: 0.098)
        )

        /// Recessed surface used for inset rows inside a card.
        static let surfaceMuted = adaptive(
            light: Color(red: 0.965, green: 0.949, blue: 0.918),
            dark: Color(red: 0.157, green: 0.145, blue: 0.129)
        )

        /// Deep Ajani teal.
        static let primary = adaptive(
            light: Color(red: 0.043, green: 0.290, blue: 0.298),
            dark: Color(red: 0.345, green: 0.776, blue: 0.745)
        )

        /// Teal wash for badges and icon backdrops.
        static let primarySoft = adaptive(
            light: Color(red: 0.882, green: 0.929, blue: 0.925),
            dark: Color(red: 0.118, green: 0.243, blue: 0.243)
        )

        /// Restrained gold, reserved for priority signals.
        static let accent = adaptive(
            light: Color(red: 0.541, green: 0.388, blue: 0.090),
            dark: Color(red: 0.894, green: 0.718, blue: 0.353)
        )

        static let accentSoft = adaptive(
            light: Color(red: 0.973, green: 0.937, blue: 0.855),
            dark: Color(red: 0.224, green: 0.180, blue: 0.086)
        )

        static let textPrimary = adaptive(
            light: Color(red: 0.086, green: 0.129, blue: 0.122),
            dark: Color(red: 0.957, green: 0.937, blue: 0.902)
        )

        static let textSecondary = adaptive(
            light: Color(red: 0.353, green: 0.388, blue: 0.376),
            dark: Color(red: 0.706, green: 0.678, blue: 0.631)
        )

        static let separator = adaptive(
            light: Color(red: 0.890, green: 0.863, blue: 0.808),
            dark: Color(red: 0.196, green: 0.184, blue: 0.165)
        )

        static let statusPlanned = adaptive(
            light: Color(red: 0.290, green: 0.353, blue: 0.420),
            dark: Color(red: 0.678, green: 0.741, blue: 0.808)
        )

        static let statusEnRoute = adaptive(
            light: Color(red: 0.604, green: 0.357, blue: 0.055),
            dark: Color(red: 0.941, green: 0.706, blue: 0.369)
        )

        static let statusArrived = adaptive(
            light: Color(red: 0.051, green: 0.361, blue: 0.451),
            dark: Color(red: 0.435, green: 0.784, blue: 0.871)
        )

        static let statusCompleted = adaptive(
            light: Color(red: 0.122, green: 0.420, blue: 0.227),
            dark: Color(red: 0.420, green: 0.816, blue: 0.561)
        )

        private static func adaptive(light: Color, dark: Color) -> Color {
            Color(uiColor: UIColor { traits in
                UIColor(traits.userInterfaceStyle == .dark ? dark : light)
            })
        }
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    enum Radius {
        static let card: CGFloat = 18
        static let inner: CGFloat = 12
    }

    enum Layout {
        /// Comfortable minimum for anything the worker taps with gloves on.
        static let minimumTapTarget: CGFloat = 48
    }
}
