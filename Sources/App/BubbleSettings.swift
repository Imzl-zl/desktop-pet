import Foundation
import SwiftUI
import DesktopPetCore

// MARK: - Token types

enum BubbleToken: String, CaseIterable, Codable, Identifiable {
    case dot, icon, title, project, separator, message, stateLabel, elapsed, model
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dot:        return "State dot"
        case .icon:       return NSLocalizedString("Agent icon", comment: "")
        case .title:      return NSLocalizedString("Chat title", comment: "")
        case .project:    return NSLocalizedString("Project folder", comment: "")
        case .separator:  return "Separator"
        case .message:    return NSLocalizedString("Activity message", comment: "")
        case .stateLabel: return NSLocalizedString("State label", comment: "")
        case .elapsed:    return NSLocalizedString("Elapsed time", comment: "")
        case .model:      return NSLocalizedString("Model", comment: "")
        }
    }

    var shortName: String {
        switch self {
        case .dot:        return NSLocalizedString("Dot", comment: "")
        case .icon:       return NSLocalizedString("Icon", comment: "")
        case .title:      return NSLocalizedString("Title", comment: "")
        case .project:    return NSLocalizedString("Project", comment: "")
        case .separator:  return "Sep"
        case .message:    return NSLocalizedString("Message", comment: "")
        case .stateLabel: return "State"
        case .elapsed:    return NSLocalizedString("Elapsed", comment: "")
        case .model:      return NSLocalizedString("Model", comment: "")
        }
    }

    var chipSymbol: String {
        switch self {
        case .dot:        return "circle.fill"
        case .icon:       return "sparkle"
        case .title:      return "text.quote"
        case .project:    return "folder.fill"
        case .separator:  return "arrow.right"
        case .message:    return "bubble.left.fill"
        case .stateLabel: return "tag.fill"
        case .elapsed:    return "clock.fill"
        case .model:      return "cpu"
        }
    }

    var chipColor: Color {
        switch self {
        case .dot:        return .orange
        case .icon:       return .purple
        case .title:      return .blue
        case .project:    return .green
        case .separator:  return .gray
        case .message:    return .indigo
        case .stateLabel: return .yellow
        case .elapsed:    return .teal
        case .model:      return .pink
        }
    }
}

struct BubbleTokenItem: Codable, Identifiable, Equatable {
    var id: String { token.rawValue }
    let token: BubbleToken
    var isVisible: Bool
}

struct BubbleLayout: Codable, Equatable {
    var tokens: [BubbleTokenItem]

    static let original = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .title,      isVisible: false),
        .init(token: .stateLabel, isVisible: false),
        .init(token: .elapsed,    isVisible: false),
        .init(token: .model,      isVisible: false),
    ])

    static let standard = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .title,      isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .stateLabel, isVisible: false),
        .init(token: .elapsed,    isVisible: false),
        .init(token: .model,      isVisible: false),
    ])

    static let detailed = BubbleLayout(tokens: [
        .init(token: .dot,        isVisible: true),
        .init(token: .icon,       isVisible: true),
        .init(token: .title,      isVisible: true),
        .init(token: .project,    isVisible: true),
        .init(token: .separator,  isVisible: true),
        .init(token: .message,    isVisible: true),
        .init(token: .stateLabel, isVisible: true),
        .init(token: .elapsed,    isVisible: true),
        .init(token: .model,      isVisible: true),
    ])

}

// MARK: - Icon choice

enum IconChoice: Equatable {
    case brandLogo(AgentKind)
    case sfSymbol(String)
}

extension IconChoice: Codable {
    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        let value = try c.decode(String.self, forKey: .value)
        switch type {
        case "brandLogo": self = .brandLogo(AgentKind(rawValue: value) ?? .unknown)
        default:          self = .sfSymbol(value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .brandLogo(let k):
            try c.encode("brandLogo", forKey: .type)
            try c.encode(k.rawValue, forKey: .value)
        case .sfSymbol(let n):
            try c.encode("sfSymbol", forKey: .type)
            try c.encode(n, forKey: .value)
        }
    }
}

// MARK: - Session grouping

/// Whether the bubble shows one row per agent kind or one row per session.
enum BubbleSessionGrouping: String, CaseIterable, Codable {
    /// Collapse sessions sharing an agent kind into one row with a ×N badge.
    case byKind
    /// Every active session gets its own row.
    case allSessions

    var displayName: String {
        switch self {
        case .byKind:      return NSLocalizedString("Grouped by agent", comment: "")
        case .allSessions: return NSLocalizedString("All sessions", comment: "")
        }
    }

    var detail: String {
        switch self {
        case .byKind:      return NSLocalizedString("One row per agent kind (×N when multiple)", comment: "")
        case .allSessions: return NSLocalizedString("One row per session", comment: "")
        }
    }
}

// MARK: - Display mode

/// How the multi-agent bubble lays out rows when more than one agent is active.
enum BubbleDisplayMode: String, CaseIterable, Codable {
    /// All rows up to `maxSessions`.
    case list
    /// One row at a time, cycling every 3 s with dot indicators (fixed height).
    case carousel
    /// Summary header, first two rows, fold for overflow.
    case compact

    var displayName: String {
        switch self {
        case .list:     return NSLocalizedString("All rows", comment: "")
        case .carousel: return NSLocalizedString("Carousel", comment: "")
        case .compact:  return NSLocalizedString("Compact", comment: "")
        }
    }

    var detail: String {
        switch self {
        case .list:     return NSLocalizedString("Show every row at once, up to the max below.", comment: "")
        case .carousel: return NSLocalizedString("One row at a time. Auto-cycles every 3 s — swipe or drag to browse.", comment: "")
        case .compact:  return NSLocalizedString("Summary header, first two rows, then fold the rest.", comment: "")
        }
    }
}

// MARK: - Min-state filter

enum MinStateFilter: String, CaseIterable, Codable {
    case all, doneAndAbove, workingAndWaiting, workingOnly

    var displayName: String {
        switch self {
        case .all:               return NSLocalizedString("All states", comment: "")
        case .doneAndAbove:      return NSLocalizedString("Done and above", comment: "")
        case .workingAndWaiting: return NSLocalizedString("Working & Waiting", comment: "")
        case .workingOnly:       return NSLocalizedString("Working only", comment: "")
        }
    }

    func includes(_ state: AgentState) -> Bool {
        // attentionPriority is internal to DesktopPetCore — compare states explicitly
        switch self {
        case .all:               return true
        case .doneAndAbove:      return state == .working || state == .waiting || state == .done
        case .workingAndWaiting: return state == .working || state == .waiting
        case .workingOnly:       return state == .working
        }
    }
}

// MARK: - BubbleSettings

@MainActor
final class BubbleSettings: ObservableObject {
    static let shared = BubbleSettings()

    enum FontSize: String, CaseIterable, Codable {
        case small, medium, large
        var primaryPt: CGFloat   { switch self { case .small: 10; case .medium: 12; case .large: 14 } }
        var secondaryPt: CGFloat { switch self { case .small: 9;  case .medium: 10.5; case .large: 12 } }
        var iconPt: CGFloat      { primaryPt + 2 }
    }

    enum Theme: String, CaseIterable, Codable {
        case light, dark, system
        var displayName: String { NSLocalizedString(rawValue.capitalized, comment: "bubble theme") }
    }

    /// Visual style for the per-row state dot.
    enum DotStyle: String, CaseIterable, Codable {
        /// Flat filled circle, color-coded by state.
        case plain
        /// Claude-Code-CLI-style spinning asterisk (✻) while active.
        case claude

        var displayName: String {
            switch self {
            case .plain:  return NSLocalizedString("Plain dot", comment: "")
            case .claude: return NSLocalizedString("Claude style", comment: "")
            }
        }

        var detail: String {
            switch self {
            case .plain:  return NSLocalizedString("Flat color-coded circle", comment: "")
            case .claude: return NSLocalizedString("Spinning ✻ asterisk while active", comment: "")
            }
        }
    }

    // MARK: Published properties

    @Published var customLayout: BubbleLayout {
        didSet { saveJSON(Keys.customLayout, customLayout) }
    }
    @Published var separatorChar: String {
        didSet { ud.set(separatorChar, forKey: Keys.separatorChar) }
    }
    @Published var fontSize: FontSize {
        didSet { ud.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }
    @Published var opacity: Double {
        didSet { ud.set(opacity, forKey: Keys.opacity) }
    }
    @Published var theme: Theme {
        didSet { ud.set(theme.rawValue, forKey: Keys.theme) }
    }
    @Published var dotStyle: DotStyle {
        didSet { ud.set(dotStyle.rawValue, forKey: Keys.dotStyle) }
    }
    @Published var maxSessions: Int {
        didSet { ud.set(maxSessions, forKey: Keys.maxSessions) }
    }
    @Published var minStateFilter: MinStateFilter {
        didSet { ud.set(minStateFilter.rawValue, forKey: Keys.minStateFilter) }
    }
    @Published var sessionGrouping: BubbleSessionGrouping {
        didSet { ud.set(sessionGrouping.rawValue, forKey: Keys.sessionGrouping) }
    }
    /// When showing all sessions, sort rows by agent kind before priority.
    @Published var groupByKind: Bool {
        didSet { ud.set(groupByKind, forKey: Keys.groupByKind) }
    }
    @Published var displayMode: BubbleDisplayMode {
        didSet { ud.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }
    /// When enabled, active sessions render with the structured multi-agent
    /// bubble. When off, DesktopPet keeps the default chat bubble behavior.
    @Published var multiAgentBubbleEnabled: Bool {
        didSet {
            ud.set(multiAgentBubbleEnabled, forKey: Keys.multiAgentBubbleEnabled)
            PetController.shared.applyBubbleModeChange()
        }
    }
    @Published var hiddenKinds: Set<AgentKind> {
        didSet { saveJSON(Keys.hiddenKinds, Array(hiddenKinds).map(\.rawValue)) }
    }
    /// Keyed by AgentKind.rawValue for JSON compatibility.
    @Published var iconChoices: [String: IconChoice] {
        didSet { saveJSON(Keys.iconChoices, iconChoices) }
    }
    @Published var activityTheme: ActivityTheme {
        didSet {
            ud.set(activityTheme.rawValue, forKey: Keys.activityTheme)
            ActivityFormatter.currentTheme = activityTheme
        }
    }
    @Published var reactiveBubblesEnabled: Bool {
        didSet { ud.set(reactiveBubblesEnabled, forKey: Keys.reactiveBubblesEnabled) }
    }

    // MARK: Computed

    var effectiveLayout: BubbleLayout { customLayout }

    func iconChoice(for kind: AgentKind) -> IconChoice {
        iconChoices[kind.rawValue] ?? .brandLogo(kind)
    }

    func setIconChoice(_ choice: IconChoice, for kind: AgentKind) {
        iconChoices[kind.rawValue] = choice
    }

    func resetIconChoice(for kind: AgentKind) {
        iconChoices.removeValue(forKey: kind.rawValue)
    }

    // MARK: Private

    private let ud = UserDefaults.standard

    private enum Keys {
        static let customLayout    = "desktoppet.bubble.customLayout"
        static let separatorChar   = "desktoppet.bubble.separatorChar"
        static let fontSize        = "desktoppet.bubble.fontSize"
        static let opacity         = "desktoppet.bubble.opacity"
        static let theme           = "desktoppet.bubble.theme"
        static let dotStyle        = "desktoppet.bubble.dotStyle"
        static let maxSessions     = "desktoppet.bubble.maxSessions"
        static let minStateFilter  = "desktoppet.bubble.minStateFilter"
        static let sessionGrouping     = "desktoppet.bubble.sessionGrouping"
        static let groupByKind         = "desktoppet.bubble.groupByKind"
        static let collapseDuplicates  = "desktoppet.bubble.collapseDuplicates" // legacy
        static let displayMode         = "desktoppet.bubble.displayMode"
        static let multiAgentBubbleEnabled = "desktoppet.bubble.multiAgentBubbleEnabled"
        static let hiddenKinds         = "desktoppet.bubble.hiddenKinds"
        static let iconChoices     = "desktoppet.bubble.iconChoices"
        static let activityTheme   = "desktoppet.bubble.activityTheme"
        static let reactiveBubblesEnabled = "desktoppet.bubble.reactiveBubblesEnabled"
    }

    init() {
        customLayout   = Self.loadJSON(Keys.customLayout) ?? .original
        separatorChar  = ud.string(forKey: Keys.separatorChar) ?? "·"
        fontSize       = FontSize(rawValue: ud.string(forKey: Keys.fontSize) ?? "") ?? .medium
        opacity        = ud.object(forKey: Keys.opacity) as? Double ?? 1.0
        theme          = Theme(rawValue: ud.string(forKey: Keys.theme) ?? "") ?? .system
        dotStyle       = DotStyle(rawValue: ud.string(forKey: Keys.dotStyle) ?? "") ?? .plain
        maxSessions    = ud.object(forKey: Keys.maxSessions) as? Int ?? 5
        minStateFilter = MinStateFilter(rawValue: ud.string(forKey: Keys.minStateFilter) ?? "") ?? .all
        sessionGrouping = Self.loadSessionGrouping()
        groupByKind     = ud.bool(forKey: Keys.groupByKind)
        displayMode = BubbleDisplayMode(rawValue: ud.string(forKey: Keys.displayMode) ?? "") ?? .carousel
        multiAgentBubbleEnabled = ud.object(forKey: Keys.multiAgentBubbleEnabled) as? Bool ?? true
        reactiveBubblesEnabled = ud.object(forKey: Keys.reactiveBubblesEnabled) as? Bool ?? true
        hiddenKinds        = Set((Self.loadJSON(Keys.hiddenKinds) as [String]? ?? []).compactMap(AgentKind.init(rawValue:)))
        iconChoices    = Self.loadJSON(Keys.iconChoices) ?? [:]
        activityTheme  = ActivityTheme(rawValue: ud.string(forKey: Keys.activityTheme) ?? "") ?? .chef
        ActivityFormatter.currentTheme = activityTheme
    }

    private func saveJSON<T: Encodable>(_ key: String, _ value: T) {
        ud.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func loadJSON<T: Decodable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func loadSessionGrouping() -> BubbleSessionGrouping {
        let ud = UserDefaults.standard
        if let raw = ud.string(forKey: Keys.sessionGrouping),
           let mode = BubbleSessionGrouping(rawValue: raw) {
            return mode
        }
        // Migrate from the old collapseDuplicates toggle.
        if ud.object(forKey: Keys.collapseDuplicates) as? Bool == false {
            return .allSessions
        }
        return .byKind
    }
}
