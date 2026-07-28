import AppKit
import DesktopPetCore

/// Loads and imports spritesheet pet packs from `~/.desktoppet/pets/`.
@MainActor
final class ImagePetStore: ObservableObject {
    static let shared = ImagePetStore()

    @Published private(set) var packs: [ImagePetPack] = []

    /// User-chosen names per pet id, overriding the pack's catalog name (#31).
    @Published private(set) var nameOverrides: [String: String] =
        (UserDefaults.standard.dictionary(forKey: "desktoppet.petNames") as? [String: String]) ?? [:]

    private var petsDir: URL {
        URL(fileURLWithPath: DesktopPetPaths.baseDir).appendingPathComponent("pets")
    }

    func pack(id: String) -> ImagePetPack? {
        packs.first { $0.id == id }
    }

    /// The name to show for a pet: the user's custom name, else the pack's
    /// catalog name, else the id. One place so every surface agrees.
    func displayName(for id: String?) -> String {
        guard let id else { return NSLocalizedString("Your pet", comment: "") }
        if let custom = nameOverrides[id], !custom.isEmpty { return custom }
        return pack(id: id)?.displayName ?? id
    }

    /// Renames a pet (empty/blank clears the override back to the catalog name).
    func rename(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == pack(id: id)?.displayName {
            nameOverrides.removeValue(forKey: id)
        } else {
            nameOverrides[id] = String(trimmed.prefix(40))
        }
        UserDefaults.standard.set(nameOverrides, forKey: "desktoppet.petNames")
        CareSyncController.shared.scheduleSync()   // push the new name to the web
    }

    /// Deletes an installed pet's folder from disk. Drops it from the in-memory
    /// list directly instead of a full `reload()`: reload re-slices every other
    /// pack's spritesheet on the main actor (heavy pixel-scan per sheet), which
    /// froze the UI when deleting with many pets installed.
    func delete(_ pack: ImagePetPack) {
        try? FileManager.default.removeItem(at: pack.directory)
        packs.removeAll { $0.id == pack.id }
    }

    /// Full synchronous reload. Used after importing a pet, where slicing every
    /// pack up front is acceptable; launch uses `loadFast` to stay responsive.
    func reload() {
        packs = Self.directories(in: petsDir)
            .compactMap { SpriteSlicer.loadPack(directory: $0) }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Launch path: slice only the prioritised pack synchronously so the pet and
    /// menu bar can appear immediately, then slice the remaining packs OFF the
    /// main thread and publish once. Slicing on the main actor (even chunked)
    /// starved the pet's frame timer at launch — the animation crawled until the
    /// library finished loading. Decoding happens on a background queue; only the
    /// finished, immutable packs are handed back to the main actor.
    func loadFast(priorityID: String?) {
        let dirs = Self.directories(in: petsDir)
        let priorityDir = priorityID
            .flatMap { pid in dirs.first { SpriteSlicer.manifestID(directory: $0) == pid } }
            ?? dirs.first
        if let pd = priorityDir, let pack = SpriteSlicer.loadPack(directory: pd) {
            packs = [pack]
        }
        let rest = dirs.filter { $0 != priorityDir }
        guard !rest.isEmpty else { return }
        Task.detached(priority: .utility) {
            let more = rest.compactMap { SpriteSlicer.loadPack(directory: $0) }
            let box = UncheckedSendableBox(more)
            await MainActor.run {
                // Keep the already-shown priority pack, add the rest, sort once.
                let store = ImagePetStore.shared
                store.packs = (store.packs + box.value).sorted { $0.displayName < $1.displayName }
            }
        }
    }

    private static func directories(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return [] }
        return entries.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}

/// Carries a non-Sendable payload (sliced `ImagePetPack`s hold `NSImage`s) from
/// a background slicing task to the main actor. Safe because the packs are
/// immutable and built fresh off-thread, then only read on the main actor.
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
