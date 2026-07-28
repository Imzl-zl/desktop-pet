import Foundation
import DesktopPetCore

/// Maps each pet state to a clip index of an imported sprite pet.
struct PetBindings: Equatable {
    var byMood: [String: Int]

    func clipIndex(for mood: PetMood) -> Int {
        byMood[mood.rawValue] ?? 0
    }

    /// Spreads the first clips across states, clamped to what the pack has.
    static func defaults(clipCount: Int) -> PetBindings {
        let order: [PetMood] = [.idle, .working, .waiting, .done, .celebrate, .sleepy, .levelup]
        var map: [String: Int] = [:]
        for (i, mood) in order.enumerated() {
            map[mood.rawValue] = clipCount > 0 ? min(i, clipCount - 1) : 0
        }
        return PetBindings(byMood: map)
    }
}

/// Persists per-pet state→clip bindings and publishes changes to the UI.
@MainActor
final class PetBindingsStore: ObservableObject {
    static let shared = PetBindingsStore()

    @Published private var cache: [String: PetBindings] = [:]

    func bindings(packId: String, clipCount: Int) -> PetBindings {
        if let cached = cache[packId] { return cached }
        let loaded = load(packId) ?? PetBindings.defaults(clipCount: clipCount)
        cache[packId] = loaded
        return loaded
    }

    func clipIndex(packId: String, clipCount: Int, mood: PetMood) -> Int {
        min(bindings(packId: packId, clipCount: clipCount).clipIndex(for: mood), max(clipCount - 1, 0))
    }

    func setClip(_ clip: Int, mood: PetMood, packId: String, clipCount: Int) {
        var current = bindings(packId: packId, clipCount: clipCount)
        current.byMood[mood.rawValue] = clip
        cache[packId] = current
        save(packId, current)
    }

    private func key(_ packId: String) -> String { "desktoppet.bindings.\(packId)" }

    private func load(_ packId: String) -> PetBindings? {
        guard let data = UserDefaults.standard.data(forKey: key(packId)),
              let map = try? JSONDecoder().decode([String: Int].self, from: data) else { return nil }
        return PetBindings(byMood: map)
    }

    private func save(_ packId: String, _ bindings: PetBindings) {
        if let data = try? JSONEncoder().encode(bindings.byMood) {
            UserDefaults.standard.set(data, forKey: key(packId))
        }
    }
}
