import Foundation
import DesktopPetCore

/// Custom messages for the multi-agent bubble, editable per agent kind (with an
/// "All agents" default). When the source is `.custom`, a non-empty line for a
/// given (agent, state) OVERRIDES the live activity / theme text in the bubble
/// row, and the real running pet honours it , not just the preview.
///
/// Working is left blank by default so live activity ("Editing X…") still shows;
/// waiting/done/celebrate ship with sensible defaults the user can edit.
@MainActor
final class BubbleMessages: ObservableObject {
    static let shared = BubbleMessages()

    enum Source: String { case system, custom }

    @Published var source: Source {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: Self.sourceKey) }
    }
    /// agentKey ("all" or AgentKind.rawValue) -> moodRawValue -> lines.
    @Published var custom: [String: [String: [String]]] {
        didSet { save() }
    }

    private static let sourceKey = "desktoppet.bubbleMsgSource"
    private static let customKey = "desktoppet.bubbleMsgCustom"

    static let allKey = "all"
    static let editableMoods: [PetMood] = [.working, .waiting, .done, .celebrate, .idle]
    static let editableAgents: [AgentKind] = [.claude, .codex, .gemini, .cursor, .opencode, .windsurf, .antigravity]

    init() {
        source = (UserDefaults.standard.string(forKey: Self.sourceKey)).flatMap(Source.init(rawValue:)) ?? .system
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let decoded = try? JSONDecoder().decode([String: [String: [String]]].self, from: data) {
            custom = decoded
        } else {
            custom = [:]
        }
    }

    /// Built-in defaults shown (and editable) per state. Working is intentionally
    /// empty so the row falls back to live activity unless the user fills it in.
    static func defaultLines(_ mood: PetMood) -> [String] {
        let base: [String]
        switch mood {
        case .waiting:   base = ["Waiting for your input", "Your turn — over to you", "Needs your input"]
        case .done:      base = PetChat.lines[.done] ?? []
        case .celebrate: base = PetChat.lines[.celebrate] ?? []
        case .idle:      base = IdleBoost.lines
        case .working:   base = []
        case .sleepy:    base = IdleBoost.lines
        case .levelup:   base = PetChat.lines[.celebrate] ?? []
        }
        return base.map { NSLocalizedString($0, comment: "bubble message") }
    }

    private func nonEmpty(_ arr: [String]?) -> [String]? {
        let filtered = (arr ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return filtered.isEmpty ? nil : filtered
    }

    /// Effective lines for an agent's state. `kind == nil` means the aggregate
    /// (the pet's overall done/celebrate line), which uses the "All agents" set.
    func lines(for kind: AgentKind?, mood: PetMood) -> [String] {
        if source == .system { return Self.defaultLines(mood) }
        if let kind, let v = nonEmpty(custom[kind.rawValue]?[mood.rawValue]) { return v }
        if let v = nonEmpty(custom[Self.allKey]?[mood.rawValue]) { return v }
        return Self.defaultLines(mood)
    }

    /// A stable line for a row, seeded by session id so multiple rows of the same
    /// kind don't all read identically and don't flicker on re-render.
    func line(for kind: AgentKind?, mood: PetMood, seed: String) -> String {
        let pool = lines(for: kind, mood: mood)
        guard !pool.isEmpty else { return "" }
        var h = 5381
        for c in seed.unicodeScalars { h = (h &* 33) &+ Int(c.value) }
        return pool[abs(h) % pool.count]
    }

    // MARK: editor binding (per agentKey + mood)

    func text(for agentKey: String, mood: PetMood) -> String {
        (custom[agentKey]?[mood.rawValue] ?? Self.defaultLines(mood)).joined(separator: "\n")
    }

    func setText(_ text: String, for agentKey: String, mood: PetMood) {
        var byMood = custom[agentKey] ?? [:]
        byMood[mood.rawValue] = text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) }
        custom[agentKey] = byMood
    }

    /// Refill a single agent key's messages with the built-in defaults.
    func resetToDefaults(for agentKey: String) {
        var byMood = custom[agentKey] ?? [:]
        for mood in Self.editableMoods { byMood[mood.rawValue] = Self.defaultLines(mood) }
        custom[agentKey] = byMood
    }

    private func save() {
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: Self.customKey)
        }
    }
}
