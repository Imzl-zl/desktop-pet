import Foundation

/// Decodes an Antigravity hook payload (camelCase JSON on stdin). Antigravity
/// does NOT send an event name, so the normalised state is inferred from which
/// discriminator fields are present, per the official hook schema:
///   • Stop          → `terminationReason` / `fullyIdle`
///   • PreToolUse    → `toolCall`
///   • Pre/PostInvocation → `invocationNum`
///   • PostToolUse   → `stepIdx`
/// The resulting `eventName` is the state's raw value, which `StateMapper`'s
/// generic decoder maps straight back to the state.
public struct AntigravityHookPayload: Decodable, Equatable {
    public let conversationId: String?
    public let workspacePaths: [String]?
    public let transcriptPath: String?
    public let toolCall: ToolCall?
    public let terminationReason: String?
    public let fullyIdle: Bool?
    public let invocationNum: Int?
    public let stepIdx: Int?
    public let model: HookModelInfo?

    public struct ToolCall: Decodable, Equatable {
        public let name: String?
        public init(name: String?) { self.name = name }
    }

    public static func decode(from data: Data) -> AntigravityHookPayload? {
        try? JSONDecoder().decode(AntigravityHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let conversationId, !conversationId.isEmpty else { return nil }
        let state: AgentState
        if terminationReason != nil || fullyIdle != nil {
            state = .done
        } else if toolCall != nil || invocationNum != nil || stepIdx != nil {
            state = .working
        } else {
            return nil
        }
        let context = ActivityFormatter.activityMessage(
            eventName: state.rawValue, sessionId: conversationId,
            toolName: toolCall?.name, toolInput: nil, explicitMessage: nil
        )
        return AgentEvent(
            sessionId: conversationId,
            agentKind: .antigravity,
            eventName: state.rawValue,
            project: workspacePaths?.first(where: { !$0.isEmpty }),
            message: context,
            model: model?.displayName,
            transcriptPath: transcriptPath,
            timestamp: now
        )
    }
}
