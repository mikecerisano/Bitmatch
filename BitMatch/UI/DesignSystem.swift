// UI/DesignSystem.swift
// Centralized design tokens for consistent styling across BitMatch.

import SwiftUI

// MARK: - Design System

/// A namespace for all design tokens used throughout the app.
/// Access tokens via nested enums: `DesignSystem.Colors.background`, `DesignSystem.Spacing.md`, etc.
enum DesignSystem {

    // MARK: - Colors

    /// Semantic color palette for the dark-themed interface.
    enum Colors {

        // MARK: Backgrounds

        /// Primary app background -- pure black.
        static let background = Color.black

        /// Elevated surface (cards, panels) -- subtle white tint over black.
        static let surface = Color.white.opacity(0.03)

        /// Slightly more prominent surface for hovered / selected elements.
        static let surfaceElevated = Color.white.opacity(0.08)

        /// Surface used for active / highlighted interactive areas.
        static let surfaceActive = Color.white.opacity(0.15)

        // MARK: Text

        /// Primary text color -- high-contrast white.
        static let textPrimary = Color.white

        /// Secondary text -- reduced emphasis.
        static let textSecondary = Color.white.opacity(0.7)

        /// Tertiary / muted text -- labels, captions, placeholders.
        static let textTertiary = Color.white.opacity(0.5)

        // MARK: Borders & Dividers

        /// Default border / divider stroke.
        static let border = Color.white.opacity(0.1)

        /// Border for selected or focused elements.
        static let borderSelected = Color.white.opacity(0.2)

        // MARK: Accent

        /// Primary accent color used for active operations and confirmation.
        static let accent = Color.green

        /// Muted accent for backgrounds behind accent-colored elements.
        static let accentMuted = Color.green.opacity(0.25)

        /// Subtle accent for hover states and faint highlights.
        static let accentSubtle = Color.green.opacity(0.4)

        // MARK: Semantic / Status

        /// Success state (verification passed, operation complete).
        static let success = Color.green

        /// Warning state (MHL generation in progress, verification pending).
        static let warning = Color.orange

        /// Error state (verification failed, operation error).
        static let error = Color.red

        /// Informational state (copy in progress, queue active).
        static let info = Color.blue

        /// Queued / idle state.
        static let idle = Color.gray

        /// Preparing / pending state.
        static let preparing = Color.yellow

        // MARK: Destructive

        /// Destructive action text.
        static let destructiveText = Color.red

        /// Destructive action background.
        static let destructiveBackground = Color.red.opacity(0.15)

        /// Destructive action border.
        static let destructiveBorder = Color.red.opacity(0.3)

        // MARK: Overlay

        /// Semi-transparent overlay for toast backgrounds, progress capsules, etc.
        static let overlayBackground = Color.black.opacity(0.6)
    }

    // MARK: - Typography

    /// Predefined font styles for consistent text rendering.
    enum Typography {

        /// Large title -- app name, primary headings.
        /// Usage: section titles, modal headers.
        static let title = Font.system(size: 16, weight: .semibold)

        /// Section heading -- card titles, group headers.
        static let heading = Font.system(size: 14, weight: .semibold)

        /// Standard body text.
        static let body = Font.system(size: 12, weight: .medium)

        /// Small supporting text -- labels, timestamps, secondary info.
        static let caption = Font.system(size: 10, weight: .regular)

        /// Extra-small text for badges, counters, and micro-labels.
        static let micro = Font.system(size: 9, weight: .semibold)

        /// Monospaced text for file names, paths, speeds, and technical readouts.
        static let mono = Font.system(size: 11, weight: .semibold, design: .monospaced)

        /// Small monospaced text for inline file info and progress details.
        static let monoSmall = Font.system(size: 10, weight: .regular, design: .monospaced)
    }

    // MARK: - Spacing

    /// Consistent spacing scale used for padding, gaps, and layout margins.
    enum Spacing {

        /// 4pt -- tight inner padding, icon-to-label gaps.
        static let xs: CGFloat = 4

        /// 8pt -- small padding, compact element spacing.
        static let sm: CGFloat = 8

        /// 16pt -- default content padding, standard gaps.
        static let md: CGFloat = 16

        /// 20pt -- card internal padding, section spacing.
        static let lg: CGFloat = 20

        /// 24pt -- generous spacing between major sections.
        static let xl: CGFloat = 24

        /// 32pt -- large layout margins, completion view padding.
        static let xxl: CGFloat = 32
    }

    // MARK: - Corner Radius

    /// Corner radius values for rounded rectangles across the UI.
    enum CornerRadius {

        /// 6pt -- buttons, small badges, inline controls.
        static let small: CGFloat = 6

        /// 8pt -- mode selector segments, medium controls.
        static let medium: CGFloat = 8

        /// 12pt -- elevated panels, grouped content areas.
        static let large: CGFloat = 12

        /// 16pt -- cards, modal sheets, completion views.
        static let xl: CGFloat = 16
    }

    // MARK: - Opacity

    /// Standard opacity levels for layered UI elements.
    enum Opacity {

        /// 0.3 -- disabled controls, inactive elements.
        static let disabled: Double = 0.3

        /// 0.5 -- secondary content, placeholder text.
        static let secondary: Double = 0.5

        /// 0.7 -- muted but readable content, de-emphasized text.
        static let muted: Double = 0.7

        /// 1.0 -- fully opaque, primary content.
        static let full: Double = 1.0
    }
}
