import SwiftUI
import DesktopPetCore

/// Body motion for a given mood at time `t`, shared by all pet renderers.
struct PetMotion {
    var offsetY: CGFloat
    var rotation: Double
    var scaleX: CGFloat
    var scaleY: CGFloat

    /// Identity: the app no longer adds body motion (no bob/sway/rotation/scale).
    /// The pet stays perfectly still and only animates through its sprite frames.
    static func resolve(_ mood: PetMood, _ t: Double) -> PetMotion {
        PetMotion(offsetY: 0, rotation: 0, scaleX: 1, scaleY: 1)
    }
}

/// Hearts that float upward and fade out when the user pets (clicks) the pet.
struct PetHearts: View {
    let size: CGFloat

    @State private var animate = false

    private static let hearts: [(x: CGFloat, y: CGFloat, scale: CGFloat)] = [
        (-0.22, -0.50, 0.8),
        ( 0.18, -0.58, 1.0),
        (-0.05, -0.70, 0.7),
        ( 0.28, -0.42, 0.9),
        (-0.30, -0.62, 0.6),
    ]

    var body: some View {
        ZStack {
            ForEach(0..<Self.hearts.count, id: \.self) { i in
                let h = Self.hearts[i]
                Image(systemName: "heart.fill")
                    .font(.system(size: 10 * h.scale))
                    .foregroundStyle(.pink)
                    .offset(
                        x: h.x * size,
                        y: animate ? h.y * size : 0
                    )
                    .opacity(animate ? 0 : 0.85)
                    .scaleEffect(animate ? 0.3 : 1.0)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animate = true
            }
        }
    }
}

/// Mood overlays shared by all pet renderers: sparkles while celebrating and a
/// "?" bubble while waiting.
struct MoodAccessories: View {
    let mood: PetMood
    let t: Double
    let size: CGFloat

    var body: some View {
        ZStack {
            if mood == .celebrate {
                ForEach(0..<4, id: \.self) { i in
                    let angle = Double(i) / 4 * .pi * 2
                    let twinkle = 0.35 + 0.65 * abs(sin(t * 4 + Double(i)))
                    Image(systemName: "sparkle")
                        .font(.system(size: 12))
                        .foregroundStyle(.yellow)
                        .opacity(twinkle)
                        .offset(x: cos(angle) * size * 0.34, y: -abs(sin(angle)) * size * 0.34 - size * 0.06)
                }
            }
        }
    }
}
