import Foundation
import DesktopPetCore

struct RemotePet: Decodable, Identifiable {
    let slug: String
    let displayName: String?
    let kind: String?
    let submittedBy: String?
    let spritesheetUrl: String
    let petJsonUrl: String
    /// Set after decoding for pets from the DesktopPet community gallery (not the
    /// upstream Petdex library); drives the "Community" badge in the UI.
    var isCommunity = false

    private enum CodingKeys: String, CodingKey {
        case slug, displayName, kind, submittedBy, spritesheetUrl, petJsonUrl
    }

    var id: String { slug }
    var name: String { displayName ?? slug }
    var author: String { let s = (submittedBy ?? "").trimmingCharacters(in: .whitespaces); return s.isEmpty ? "community" : s }
}

/// Decodes `T` but tolerates a malformed element (yields `nil` instead of
/// failing the whole array).
private struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) {
        value = try? T(from: decoder)
    }
}

/// Loads the online pet library and downloads packs into `~/.desktoppet/pets/`.
@MainActor
final class PetBrowser: ObservableObject {
    @Published var pets: [RemotePet] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var query = ""
    @Published var category = "all"   // all / character / creature / object
    @Published var downloading: Set<String> = []
    @Published var installed: Set<String> = []
    /// A transient per-download failure, shown as a banner without hiding the list.
    @Published var downloadError: String?

    static let categories: [(label: String, value: String)] = [
        ("All", "all"), ("Characters", "character"), ("Creatures", "creature"), ("Objects", "object"),
    ]

    // Two sources, merged into one list:
    //  • Petdex — via our caching proxy (rewrites asset URLs through R2 so we
    //    don't hit Petdex's rate-limited CDN; see README acknowledgements).
    //  • Community — pets uploaded to DesktopPet's own gallery, surfaced first.
    private static let petdexURL = URL(string: "https://pets.thenightwatcher.online/manifest.json")!
    private static let communityURL = URL(string: "https://agentpet.thenightwatcher.online/api/pets")!

    private struct Manifest: Decodable {
        let pets: [RemotePet]
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            pets = try container.decode([Lenient<RemotePet>].self, forKey: .pets).compactMap(\.value)
        }
        enum CodingKeys: String, CodingKey { case pets }
    }
    var results: [RemotePet] {
        var list = pets
        if category != "all" {
            list = list.filter { $0.kind == category }
        }
        guard !query.isEmpty else { return list }
        let q = query.lowercased()
        return list.filter { $0.name.lowercased().contains(q) || $0.slug.contains(q) }
    }

    func loadIfNeeded() {
        // Mark pets already on disk as added.
        installed = Set(ImagePetStore.shared.packs.map(\.id))
        guard pets.isEmpty, !isLoading else { return }
        isLoading = true
        errorText = nil
        Task {
            // Fetch both sources concurrently; either failing alone is tolerated.
            async let community = Self.fetch(Self.communityURL, isCommunity: true)
            async let library = Self.fetch(Self.petdexURL, isCommunity: false)
            // Shuffle the library so the order isn't identical to the source site;
            // community pets stay first. Shuffled once per load.
            let merged = Self.dedupe(await community + (await library).shuffled())
            if merged.isEmpty {
                self.errorText = "Couldn't load the pet library. Check your connection."
            } else {
                self.pets = merged
            }
            self.isLoading = false
        }
    }

    /// Loads one manifest; retries once on transient failures. Returns `[]` on
    /// permanent failure so the other source still shows.
    private static func fetch(_ url: URL, isCommunity: Bool) async -> [RemotePet] {
        for attempt in 0..<2 {
            do {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                let (data, response) = try await URLSession.shared.data(for: request)
                let code = (response as? HTTPURLResponse)?.statusCode ?? 200
                if (200..<300).contains(code) {
                    var list = try JSONDecoder().decode(Manifest.self, from: data).pets
                    if isCommunity { for i in list.indices { list[i].isCommunity = true } }
                    return list
                }
                guard code == 429 || code >= 500, attempt < 1 else { return [] }
            } catch {
                guard attempt < 1 else { return [] }
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }
        return []
    }

    /// Keeps the first occurrence of each slug (community entries come first).
    private static func dedupe(_ list: [RemotePet]) -> [RemotePet] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.slug).inserted }
    }

    func download(_ pet: RemotePet) {
        guard !downloading.contains(pet.slug) else { return }
        downloadError = nil
        downloading.insert(pet.slug)
        Task {
            await performDownload(pet)
            self.downloading.remove(pet.slug)
        }
    }

    private func performDownload(_ pet: RemotePet) async {
        guard let petJsonURL = URL(string: pet.petJsonUrl),
              let sheetURL = URL(string: pet.spritesheetUrl) else { return }
        do {
            let id = try await PetInstaller.download(slug: pet.slug, petJsonURL: petJsonURL, spritesheetURL: sheetURL)
            ImagePetStore.shared.reload()
            installed.insert(pet.slug)
            PetController.shared.selectedPetID = id
            downloadError = nil
        } catch {
            // A single failed download must not blank the whole gallery.
            downloadError = PetInstaller.message(for: error, pet: pet.name)
        }
    }
}
