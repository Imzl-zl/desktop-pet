import Foundation

/// A snapshot of a completed agent session, persisted to disk for historical review.
public struct SessionArchive: Codable, Sendable {
    public let sessionId: String
    public let agentKind: AgentKind
    public let project: String?
    public let title: String?
    public let message: String?
    public let tokenCount: Int?
    public let startedAt: Date
    public let endedAt: Date
    public let duration: TimeInterval

    public init(
        sessionId: String,
        agentKind: AgentKind,
        project: String?,
        title: String?,
        message: String?,
        tokenCount: Int?,
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval
    ) {
        self.sessionId = sessionId
        self.agentKind = agentKind
        self.project = project
        self.title = title
        self.message = message
        self.tokenCount = tokenCount
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.duration = duration
    }
}
