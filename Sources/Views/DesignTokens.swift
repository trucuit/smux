import SwiftUI

// MARK: - Design Tokens

/// Centralized design tokens for smux.
/// All colors, spacing, and radii live here — no raw hex in views.
enum Tokens {

    // MARK: Backgrounds

    /// Terminal content background
    static let bgTerminal = Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1))
    /// Pane title bar background
    static let bgTitlebar = Color(nsColor: NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1))
    /// Workspace canvas background (behind all panes)
    static let bgWorkspace = Color(nsColor: NSColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1))

    // MARK: Terminal text

    /// Terminal foreground (passed to SwiftTerm as NSColor)
    static let termForeground = NSColor(red: 0.85, green: 0.85, blue: 0.85, alpha: 1)
    /// Terminal background (passed to SwiftTerm as NSColor)
    static let termBackground = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1)

    // MARK: Borders

    static let borderDim = Color(nsColor: NSColor(red: 0.22, green: 0.22, blue: 0.24, alpha: 1))

    // MARK: Semantic accent colors

    /// Pane needs user attention (watch mode triggered)
    static let attention = Color(red: 0.9, green: 0.55, blue: 0.1)
    /// Pane has active running process
    static let active = Color(red: 0.2, green: 0.55, blue: 0.3)
    /// Pane is focused / selected
    static let focus = Color(red: 0.35, green: 0.55, blue: 0.95)

    // MARK: Text opacity (on dark backgrounds)

    /// Primary text on dark bg — high contrast
    static let textPrimary: Double = 0.9
    /// Secondary text on dark bg
    static let textSecondary: Double = 0.55
    /// Muted / disabled text on dark bg
    static let textMuted: Double = 0.35

    // MARK: Radii

    /// Pane corner radius
    static let paneRadius: CGFloat = 10
    /// Sidebar row corner radius
    static let rowRadius: CGFloat = 6
    /// Search overlay corner radius
    static let overlayRadius: CGFloat = 8

    // MARK: Spacing

    static let paneGap: CGFloat = 4
    static let titlebarPaddingH: CGFloat = 10
    static let titlebarPaddingV: CGFloat = 4
    static let terminalPaddingH: CGFloat = 8

    // MARK: Borders

    static let borderFocused: CGFloat = 1.5
    static let borderDefault: CGFloat = 1

    // MARK: Typography

    static let fontFamily = "Intel One Mono"
    /// Terminal font size
    static let terminalFontSize: CGFloat = 13
    /// Resolve the terminal NSFont, falling back to system monospaced if unavailable.
    static var terminalFont: NSFont {
        NSFont(name: fontFamily, size: terminalFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
    }

    // MARK: Animation

    static let stateTransition: Animation = .easeInOut(duration: 0.15)
}
