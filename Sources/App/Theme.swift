import SwiftUI
import AppKit

extension Color {
    /// The real system accent color, which (unlike `Color.accentColor`) does
    /// not dim to gray when the window is not key.
    static var systemAccent: Color { Color(nsColor: .controlAccentColor) }
}

// MARK: - Design tokens

/// Premium dark companion theme shared across Settings, onboarding, the menu
/// bar popover and the pet HUD. Tokens are semantic so the same surface can
/// be rebuilt consistently without scattering raw values.
enum Theme {
    // Backgrounds
    static let bgTop = Color(red: 0.03, green: 0.04, blue: 0.10)
    static let bgBottom = Color(red: 0.08, green: 0.05, blue: 0.18)
    static let bgElevated = Color(red: 0.11, green: 0.09, blue: 0.22)

    // Accent
    static let accent = Color(red: 0.50, green: 0.42, blue: 1.00)
    static let accentSoft = accent.opacity(0.18)
    static let accentGlow = accent.opacity(0.35)

    // Cards
    static let card = Color.white.opacity(0.055)
    static let cardHover = Color.white.opacity(0.085)
    static let cardStroke = Color.white.opacity(0.10)
    static let cardStrokeStrong = Color.white.opacity(0.16)

    // Text
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.72)
    static let textMuted = Color(red: 0.62, green: 0.65, blue: 0.82)
    static let textDisabled = Color.white.opacity(0.38)

    // Functional
    static let success = Color(red: 0.24, green: 0.86, blue: 0.55)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.30)
    static let danger = Color(red: 1.00, green: 0.45, blue: 0.45)
    static let info = Color(red: 0.35, green: 0.65, blue: 1.00)

    // Functional soft fills (badges / chips)
    static let successSoft = success.opacity(0.14)
    static let warningSoft = warning.opacity(0.14)
    static let dangerSoft = danger.opacity(0.14)
    static let infoSoft = info.opacity(0.14)

    // Companion evolution stage palette (matches the dark navy theme).
    static let stageColors: [(top: Color, bottom: Color, glyph: String)] = [
        (Color(red: 0.28, green: 0.78, blue: 0.48), Color(red: 0.14, green: 0.52, blue: 0.30), "leaf.fill"),
        (Color(red: 0.22, green: 0.74, blue: 0.72), Color(red: 0.10, green: 0.48, blue: 0.52), "pawprint.fill"),
        (Color(red: 0.34, green: 0.58, blue: 0.96), Color(red: 0.16, green: 0.34, blue: 0.82), "binoculars.fill"),
        (Color(red: 0.64, green: 0.42, blue: 0.94), Color(red: 0.42, green: 0.22, blue: 0.78), "shield.lefthalf.filled"),
        (Color(red: 0.96, green: 0.74, blue: 0.28), Color(red: 0.86, green: 0.48, blue: 0.12), "crown.fill"),
    ]

    // Shadows
    static let shadowColor = Color.black.opacity(0.28)
    static let shadowRadius: CGFloat = 16
    static let shadowX: CGFloat = 0
    static let shadowY: CGFloat = 5

    // Radius
    static let radiusSm: CGFloat = 8
    static let radiusMd: CGFloat = 12
    static let radiusLg: CGFloat = 16
    static let radiusXl: CGFloat = 20

    // Spacing (4-point grid)
    static let space1: CGFloat = 4
    static let space2: CGFloat = 8
    static let space3: CGFloat = 12
    static let space4: CGFloat = 16
    static let space5: CGFloat = 20
    static let space6: CGFloat = 24
    static let space8: CGFloat = 32

    // Animation
    static let spring = Animation.interpolatingSpring(stiffness: 320, damping: 24)
    static let easeFast = Animation.easeOut(duration: 0.18)
    static let easeMedium = Animation.easeInOut(duration: 0.28)

    /// Full Settings / onboarding background: deep midnight gradient with a
    /// soft accent glow anchored at the top-trailing corner.
    static var background: some View {
        LinearGradient(colors: [bgTop, bgBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            .overlay(
                RadialGradient(colors: [accent.opacity(0.22), .clear],
                               center: .topTrailing, startRadius: 20, endRadius: 600)
            )
            .ignoresSafeArea()
    }

    /// Compact glow used behind hero avatars or selected states.
    static func glow(_ color: Color = accent, radius: CGFloat = 28) -> some View {
        color.opacity(0.30)
            .blur(radius: radius)
    }
}

// MARK: - Typography helpers

extension Font {
    static func ui(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: size, weight: weight, design: design)
    }
}

// MARK: - Labels

/// Small uppercase tracked label, e.g. "YOUR PET".
struct EyebrowLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.ui(size: 10, weight: .semibold))
            .tracking(1.4)
            .foregroundStyle(Theme.textMuted)
    }
}

// MARK: - Cards

private struct CardModifier: ViewModifier {
    var padding: CGFloat = Theme.space4
    var radius: CGFloat = Theme.radiusLg
    var fill: Color = Theme.card
    var stroke: Color = Theme.cardStroke
    var shadow: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(stroke, lineWidth: 1))
            .shadow(color: shadow ? Theme.shadowColor : .clear,
                    radius: shadow ? Theme.shadowRadius : 0,
                    x: Theme.shadowX,
                    y: shadow ? Theme.shadowY : 0)
    }
}

extension View {
    func themedCard(padding: CGFloat = Theme.space4,
                    radius: CGFloat = Theme.radiusLg,
                    fill: Color = Theme.card,
                    stroke: Color = Theme.cardStroke,
                    shadow: Bool = false) -> some View {
        modifier(CardModifier(padding: padding, radius: radius, fill: fill, stroke: stroke, shadow: shadow))
    }
}

// MARK: - Buttons

/// A subtle footer/control button used in popovers and HUDs.
struct PillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 12, weight: .medium))
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space2)
            .background(Theme.card.opacity(configuration.isPressed ? 0.18 : 0.10))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous).strokeBorder(Theme.cardStroke, lineWidth: 1))
            .foregroundStyle(Theme.textSecondary)
            .cornerRadius(Theme.radiusMd)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.easeFast, value: configuration.isPressed)
    }
}

/// Primary call-to-action button for onboarding and Settings bottom bars.
struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 13, weight: .semibold))
            .padding(.horizontal, Theme.space4)
            .padding(.vertical, Theme.space3)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(Theme.accent.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
            .foregroundStyle(.white)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.easeFast, value: configuration.isPressed)
    }
}

/// Bordered secondary button for grouped forms and sheets.
struct BorderedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ui(size: 12, weight: .medium))
            .padding(.horizontal, Theme.space3)
            .padding(.vertical, Theme.space2)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .fill(Theme.card.opacity(configuration.isPressed ? 0.12 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusMd, style: .continuous)
                    .strokeBorder(Theme.cardStrokeStrong, lineWidth: 1)
            )
            .foregroundStyle(Theme.textSecondary)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(Theme.easeFast, value: configuration.isPressed)
    }
}
