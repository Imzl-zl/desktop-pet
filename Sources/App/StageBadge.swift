import SwiftUI
import DesktopPetCore

/// A glossy medal for an evolution stage: a gradient disc, a soft ring, and a
/// white stage glyph. Used wherever a pet's rank is shown.
struct StageBadge: View {
    let stageIndex: Int
    var size: CGFloat = 26

    private static let palette: [(Color, Color, String)] = [
        (Color(red: 0.30, green: 0.80, blue: 0.45), Color(red: 0.16, green: 0.60, blue: 0.32), "leaf.fill"),       // Hatchling
        (Color(red: 0.25, green: 0.80, blue: 0.74), Color(red: 0.10, green: 0.55, blue: 0.55), "pawprint.fill"),  // Companion
        (Color(red: 0.36, green: 0.62, blue: 0.98), Color(red: 0.16, green: 0.40, blue: 0.85), "binoculars.fill"),// Scout
        (Color(red: 0.69, green: 0.45, blue: 0.97), Color(red: 0.47, green: 0.25, blue: 0.82), "shield.lefthalf.filled"), // Hero
        (Color(red: 1.00, green: 0.78, blue: 0.28), Color(red: 0.92, green: 0.52, blue: 0.10), "crown.fill"),     // Legend
    ]

    private var entry: (Color, Color, String) {
        Self.palette[min(max(stageIndex, 0), Self.palette.count - 1)]
    }

    var body: some View {
        let (top, bottom, glyph) = entry
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom))
            Circle()
                .strokeBorder(.white.opacity(0.5), lineWidth: size * 0.05)
            // Glossy highlight.
            Ellipse()
                .fill(.white.opacity(0.28))
                .frame(width: size * 0.6, height: size * 0.32)
                .offset(y: -size * 0.22)
                .blur(radius: size * 0.02)
            Image(systemName: glyph)
                .font(.system(size: size * 0.46, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: bottom.opacity(0.6), radius: 0.5, y: 0.5)
        }
        .frame(width: size, height: size)
        .shadow(color: bottom.opacity(0.4), radius: size * 0.08, y: size * 0.04)
    }
}
