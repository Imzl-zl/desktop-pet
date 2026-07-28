import Foundation

/// The pet's mood, derived from the aggregate of all agent sessions. Also the
/// set of animation states a pet pack must provide.
public enum PetMood: String, Codable, Sendable, CaseIterable {
    case idle
    case working
    case waiting
    case done
    case celebrate
    /// Resting during a break reminder (app-layer override, not a session state).
    case sleepy
    /// Transient burst when the pet levels up (app-layer transient, like celebrate).
    case levelup
}

/// Reduces all sessions to a single mood by attention priority.
/// `celebrate` is never returned here; it is a transient the pet controller
/// plays when entering `done` (see the app layer).
public enum MoodResolver {
    public static func aggregate(_ sessions: [AgentSession]) -> PetMood {
        // Running work takes priority: the pet reflects what is active now.
        // `registered` (agent open but idle) is not "working".
        if sessions.contains(where: { $0.state == .working }) { return .working }
        if sessions.contains(where: { $0.state == .waiting }) { return .waiting }
        if sessions.contains(where: { $0.state == .done }) { return .done }
        return .idle
    }
}
