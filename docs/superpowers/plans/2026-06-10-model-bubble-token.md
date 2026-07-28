# Model Bubble Token Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show the LLM model name (e.g. "Sonnet 4.6", "GPT-5.1") on the bubble chat line, auto-detected from each agent's hook payload, as a new optional `BubbleToken`.

**Architecture:** A new shape-tolerant `HookModelInfo` decoder extracts a display name from each agent's `model` hook field (or `nil` if absent/malformed, never failing the whole decode). This flows `AgentEvent.model` → `SessionStore` (sticky merge into `AgentSession.model`) → a new `BubbleToken.model` rendered by `AgentRow`, hidden when `nil` (same pattern as `.title`).

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager.

---

### Task 1: `HookModelInfo` decoder + `AgentEvent.model`

**Files:**
- Modify: `Sources/DesktopPetCore/HookPayloads.swift`
- Modify: `Sources/DesktopPetCore/AgentEvent.swift`
- Test: `Tests/DesktopPetCoreTests/ClaudeHookPayloadTests.swift`

- [ ] **Step 1: Add `HookModelInfo` to `HookPayloads.swift`**

Insert at the top of `Sources/DesktopPetCore/HookPayloads.swift`, right after `import Foundation` (before the `CursorHookPayload` struct):

```swift
/// Decodes a hook payload's `model` field into a display name. Tolerates
/// every shape we might see — `{"display_name": "...", "id": "..."}`,
/// `{"id": "..."}` only, a bare string, or the key being absent entirely —
/// and never throws, so an unexpected `model` shape can't fail the decode
/// of the surrounding hook payload.
public struct HookModelInfo: Decodable, Equatable {
    public let displayName: String?

    private enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case id
    }

    public init(from decoder: Decoder) throws {
        if let c = try? decoder.container(keyedBy: CodingKeys.self) {
            let name = (try? c.decodeIfPresent(String.self, forKey: .displayName)) ?? nil
            let id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? nil
            displayName = name ?? id
        } else if let single = try? decoder.singleValueContainer(),
                  let str = try? single.decode(String.self) {
            displayName = str
        } else {
            displayName = nil
        }
    }
}
```

- [ ] **Step 2: Add `model` field to `AgentEvent`**

In `Sources/DesktopPetCore/AgentEvent.swift`, add the field and thread it through the initializer:

```swift
public struct AgentEvent: Codable, Sendable, Equatable {
    public var sessionId: String
    public var agentKind: AgentKind
    public var eventName: String
    public var project: String?
    public var message: String?
    /// Display name of the LLM model in use (e.g. "Sonnet 4.6"), if the hook
    /// payload included one. `nil` when the agent doesn't report it.
    public var model: String?
    /// Path to the agent's conversation transcript file (e.g. Claude Code JSONL).
    /// Used to derive a human-readable title for the session.
    public var transcriptPath: String?
    public var timestamp: Date

    public init(
        sessionId: String,
        agentKind: AgentKind,
        eventName: String,
        project: String? = nil,
        message: String? = nil,
        model: String? = nil,
        transcriptPath: String? = nil,
        timestamp: Date
    ) {
        self.sessionId = sessionId
        self.agentKind = agentKind
        self.eventName = eventName
        self.project = project
        self.message = message
        self.model = model
        self.transcriptPath = transcriptPath
        self.timestamp = timestamp
    }
}
```

- [ ] **Step 3: Write failing tests for `HookModelInfo` via `ClaudeHookPayload`**

These tests reference `ClaudeHookPayload.model` which doesn't exist yet (added in Task 2) — write them now so Task 2 has a red test to turn green. Add to `Tests/DesktopPetCoreTests/ClaudeHookPayloadTests.swift`, inside `final class ClaudeHookPayloadTests`, after `testNilWhenMissingEssentialFields`:

```swift
    // MARK: - model field

    func testDecodesModelDisplayName() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":{"id":"claude-sonnet-4-6-20250514","display_name":"Sonnet 4.6"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.model, "Sonnet 4.6")
    }

    func testFallsBackToModelIdWhenNoDisplayName() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":{"id":"gpt-5.1"}}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.model, "gpt-5.1")
    }

    func testDecodesBareStringModel() {
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":"some-model"}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.model, "some-model")
    }

    func testNilModelWhenAbsent() {
        let json = #"{"session_id":"s","hook_event_name":"Stop"}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertNil(event?.model)
    }

    func testMalformedModelDoesNotBreakDecode() {
        // model is a number, not an object/string — must not fail the whole payload.
        let json = #"{"session_id":"s","hook_event_name":"Stop","model":123}"#
        let event = payload(json)?.makeEvent(now: now)
        XCTAssertEqual(event?.eventName, "Stop", "payload must still decode")
        XCTAssertNil(event?.model)
    }
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --filter ClaudeHookPayloadTests`
Expected: FAIL — `value of type 'ClaudeHookPayload' has no member 'model'` (compile error) until Task 2's Step 1 lands. That's expected; Task 2 makes this compile and pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/DesktopPetCore/HookPayloads.swift Sources/DesktopPetCore/AgentEvent.swift Tests/DesktopPetCoreTests/ClaudeHookPayloadTests.swift
git commit -m "feat: add HookModelInfo decoder and AgentEvent.model field"
```

---

### Task 2: Decode `model` in `ClaudeHookPayload` (covers Claude/Codex/Gemini/opencode/Copilot/Kiro)

**Files:**
- Modify: `Sources/DesktopPetCore/ClaudeHookPayload.swift`
- Test: `Tests/DesktopPetCoreTests/ClaudeHookPayloadTests.swift` (already written in Task 1)

- [ ] **Step 1: Add `model` field and pass it through `makeEvent`**

Replace the full contents of `Sources/DesktopPetCore/ClaudeHookPayload.swift` with:

```swift
import Foundation

/// The JSON Claude Code writes to a hook's stdin. Only the fields DesktopPet
/// needs are decoded; the rest are ignored.
public struct ClaudeHookPayload: Decodable, Equatable {
    public let sessionId: String?
    public let cwd: String?
    public let hookEventName: String?
    public let message: String?
    public let toolName: String?
    public let toolInput: ToolActivityInput?
    public let model: HookModelInfo?
    /// Absolute path to the conversation's JSONL transcript file.
    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case cwd
        case hookEventName = "hook_event_name"
        case message
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case model
        case transcriptPath = "transcript_path"
    }

    public static func decode(from data: Data) -> ClaudeHookPayload? {
        try? JSONDecoder().decode(ClaudeHookPayload.self, from: data)
    }

    /// Builds an `AgentEvent` from the payload, or `nil` if the essential
    /// fields (session id and event name) are missing.
    public func makeEvent(now: Date, kind: AgentKind = .claude) -> AgentEvent? {
        guard let sessionId, let hookEventName else { return nil }
        let context = ActivityFormatter.activityMessage(
            eventName: hookEventName,
            sessionId: sessionId,
            toolName: toolName,
            toolInput: toolInput,
            explicitMessage: message
        ) ?? toolName.map { "Using \($0)" }
        return AgentEvent(
            sessionId: sessionId, agentKind: kind, eventName: hookEventName,
            project: cwd, message: context, model: model?.displayName,
            transcriptPath: transcriptPath, timestamp: now
        )
    }
}
```

- [ ] **Step 2: Run tests to verify they pass**

Run: `swift test --filter ClaudeHookPayloadTests`
Expected: PASS — all 5 new tests plus the existing ones green.

- [ ] **Step 3: Commit**

```bash
git add Sources/DesktopPetCore/ClaudeHookPayload.swift
git commit -m "feat: decode model field in ClaudeHookPayload"
```

---

### Task 3: Decode `model` in Cursor, Windsurf, Antigravity payloads

**Files:**
- Modify: `Sources/DesktopPetCore/HookPayloads.swift`
- Modify: `Sources/DesktopPetCore/AntigravityHookPayload.swift`
- Test: `Tests/DesktopPetCoreTests/MultiAgentHookTests.swift`
- Test: `Tests/DesktopPetCoreTests/AntigravityHookPayloadTests.swift`

- [ ] **Step 1: Add `model` to `CursorHookPayload`**

In `Sources/DesktopPetCore/HookPayloads.swift`, replace the `CursorHookPayload` struct (everything from `public struct CursorHookPayload` through its closing `}`) with:

```swift
/// The JSON Cursor writes to a hook's stdin (only the fields DesktopPet needs).
public struct CursorHookPayload: Decodable, Equatable {
    public let conversationId: String?
    public let hookEventName: String?
    public let workspaceRoots: [String]?
    public let toolName: String?
    public let toolInput: ToolActivityInput?
    public let model: HookModelInfo?

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case hookEventName = "hook_event_name"
        case workspaceRoots = "workspace_roots"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case model
    }

    public static func decode(from data: Data) -> CursorHookPayload? {
        try? JSONDecoder().decode(CursorHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let conversationId, let hookEventName else { return nil }
        let context = ActivityFormatter.activityMessage(
            eventName: hookEventName, sessionId: conversationId,
            toolName: toolName, toolInput: toolInput, explicitMessage: nil
        )
        return AgentEvent(
            sessionId: conversationId, agentKind: .cursor, eventName: hookEventName,
            project: workspaceRoots?.first, message: context, model: model?.displayName,
            timestamp: now
        )
    }
}
```

- [ ] **Step 2: Add `model` to `WindsurfHookPayload`**

In the same file, replace the `WindsurfHookPayload` struct with:

```swift
/// The JSON Windsurf (Cascade) writes to a hook's stdin.
public struct WindsurfHookPayload: Decodable, Equatable {
    public let trajectoryId: String?
    public let agentActionName: String?
    public let model: HookModelInfo?

    enum CodingKeys: String, CodingKey {
        case trajectoryId = "trajectory_id"
        case agentActionName = "agent_action_name"
        case model
    }

    public static func decode(from data: Data) -> WindsurfHookPayload? {
        try? JSONDecoder().decode(WindsurfHookPayload.self, from: data)
    }

    public func makeEvent(now: Date) -> AgentEvent? {
        guard let trajectoryId, let agentActionName else { return nil }
        return AgentEvent(
            sessionId: trajectoryId, agentKind: .windsurf, eventName: agentActionName,
            project: nil, message: nil, model: model?.displayName, timestamp: now
        )
    }
}
```

- [ ] **Step 3: Add `model` to `AntigravityHookPayload`**

In `Sources/DesktopPetCore/AntigravityHookPayload.swift`, add the field to the struct (after `public let stepIdx: Int?`):

```swift
    public let stepIdx: Int?
    public let model: HookModelInfo?
```

Then update `makeEvent` to pass it through — replace the `return AgentEvent(...)` block at the end of `makeEvent` with:

```swift
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
```

- [ ] **Step 4: Write tests**

Add to `Tests/DesktopPetCoreTests/MultiAgentHookTests.swift`, near the other Cursor/Windsurf decode tests (e.g. after `testCursorPayloadDecode`):

```swift
    func testCursorPayloadDecodesModel() {
        let json = #"{"conversation_id":"c1","hook_event_name":"stop","model":{"display_name":"Sonnet 4.6"}}"#
        let e = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        XCTAssertEqual(e?.model, "Sonnet 4.6")
    }

    func testCursorPayloadModelAbsentIsNil() {
        let json = #"{"conversation_id":"c1","hook_event_name":"stop"}"#
        let e = HookPayload.event(forAgent: .cursor, stdin: Data(json.utf8), now: Date())
        XCTAssertNil(e?.model)
    }

    func testWindsurfPayloadDecodesModel() {
        let json = #"{"trajectory_id":"t1","agent_action_name":"post_cascade_response","model":{"display_name":"GPT-5.1"}}"#
        let e = HookPayload.event(forAgent: .windsurf, stdin: Data(json.utf8), now: Date())
        XCTAssertEqual(e?.model, "GPT-5.1")
    }
```

Add to `Tests/DesktopPetCoreTests/AntigravityHookPayloadTests.swift`, after `testPreToolUseIsWorking`:

```swift
    func testDecodesModel() {
        let e = event(#"{"conversationId":"c1","workspacePaths":["/p"],"stepIdx":0,"toolCall":{"name":"run_command"},"model":{"display_name":"Gemini 3 Pro"}}"#)
        XCTAssertEqual(e?.model, "Gemini 3 Pro")
    }
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter MultiAgentHookTests && swift test --filter AntigravityHookPayloadTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/DesktopPetCore/HookPayloads.swift Sources/DesktopPetCore/AntigravityHookPayload.swift Tests/DesktopPetCoreTests/MultiAgentHookTests.swift Tests/DesktopPetCoreTests/AntigravityHookPayloadTests.swift
git commit -m "feat: decode model field for Cursor, Windsurf, Antigravity payloads"
```

---

### Task 4: `AgentSession.model` + sticky merge in `SessionStore`

**Files:**
- Modify: `Sources/DesktopPetCore/AgentSession.swift`
- Modify: `Sources/DesktopPetCore/SessionStore.swift`
- Test: `Tests/DesktopPetCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Add `model` to `AgentSession`**

Replace the full contents of `Sources/DesktopPetCore/AgentSession.swift` with:

```swift
import Foundation

/// Current known state of one agent session.
public struct AgentSession: Identifiable, Sendable, Equatable {
    public let id: String
    public var agentKind: AgentKind
    public var project: String?
    /// Human-readable conversation title (e.g. Claude Code's summary, or first
    /// user message). Populated lazily from the transcript when available.
    public var title: String?
    public var state: AgentState
    public var message: String?
    /// Display name of the LLM model in use (e.g. "Sonnet 4.6"), if any hook
    /// event for this session reported one. Sticky: once set, persists across
    /// later events that omit it.
    public var model: String?
    public var source: AgentSource
    public var updatedAt: Date
    /// When the session entered its current `state`; resets on state change.
    public var stateSince: Date

    public init(
        id: String,
        agentKind: AgentKind,
        project: String? = nil,
        title: String? = nil,
        state: AgentState,
        message: String? = nil,
        model: String? = nil,
        source: AgentSource,
        updatedAt: Date,
        stateSince: Date? = nil
    ) {
        self.id = id
        self.agentKind = agentKind
        self.project = project
        self.title = title
        self.state = state
        self.message = message
        self.model = model
        self.source = source
        self.updatedAt = updatedAt
        self.stateSince = stateSince ?? updatedAt
    }
}
```

- [ ] **Step 2: Write failing test for sticky merge**

Add to `Tests/DesktopPetCoreTests/SessionStoreTests.swift`, inside `final class SessionStoreTests`, after `testApplyUpdatesExistingAndKeepsProjectWhenNil`:

```swift
    func testApplyKeepsModelWhenLaterEventOmitsIt() {
        let store = SessionStore()
        let withModel = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
            project: "/proj", message: nil, model: "Sonnet 4.6", timestamp: t0
        )
        store.apply(withModel, now: t0)

        let withoutModel = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "Stop",
            project: "/proj", message: nil, model: nil, timestamp: t0.addingTimeInterval(5)
        )
        let updated = store.apply(withoutModel, now: t0.addingTimeInterval(5))

        XCTAssertEqual(updated?.model, "Sonnet 4.6", "model should persist when a later event omits it")
    }

    func testApplySetsModelOnNewSession() {
        let store = SessionStore()
        let withModel = AgentEvent(
            sessionId: "s1", agentKind: .claude, eventName: "SessionStart",
            project: "/proj", message: nil, model: "Sonnet 4.6", timestamp: t0
        )
        let s = store.apply(withModel, now: t0)
        XCTAssertEqual(s?.model, "Sonnet 4.6")
    }
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `swift test --filter SessionStoreTests`
Expected: FAIL — both new tests fail because `AgentSession.model` is always `nil` (apply doesn't set it yet).

- [ ] **Step 4: Update `SessionStore.apply`**

In `Sources/DesktopPetCore/SessionStore.swift`, replace the body of `apply(_:now:)` from `if var existing = byID[event.sessionId] {` through the end of the function (the `return session` line) with:

```swift
        if var existing = byID[event.sessionId] {
            if existing.state != state { existing.stateSince = now }
            existing.state = state
            existing.updatedAt = now
            if let project = event.project { existing.project = project }
            if let model = event.model { existing.model = model }
            existing.message = event.message
            byID[event.sessionId] = existing
            return existing
        }
        let session = AgentSession(
            id: event.sessionId,
            agentKind: event.agentKind,
            project: event.project,
            state: state,
            message: event.message,
            model: event.model,
            source: .hook,
            updatedAt: now
        )
        byID[event.sessionId] = session
        return session
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter SessionStoreTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/DesktopPetCore/AgentSession.swift Sources/DesktopPetCore/SessionStore.swift Tests/DesktopPetCoreTests/SessionStoreTests.swift
git commit -m "feat: add sticky AgentSession.model populated from hook events"
```

---

### Task 5: New `BubbleToken.model` + layout presets

**Files:**
- Modify: `Sources/App/BubbleSettings.swift`
- Test: `Tests/DesktopPetAppTests/BubbleSettingsTests.swift`

- [ ] **Step 1: Write failing tests for the new token and presets**

Add to `Tests/DesktopPetAppTests/BubbleSettingsTests.swift`, inside `final class BubbleSettingsTests`, after `testSessionGroupingMigratesFromLegacyCollapseOff`:

```swift
    func testModelTokenExistsAndHasMetadata() {
        XCTAssertTrue(BubbleToken.allCases.contains(.model))
        XCTAssertEqual(BubbleToken.model.shortName, "Model")
        XCTAssertEqual(BubbleToken.model.chipSymbol, "cpu")
    }

    func testModelTokenVisibilityInPresets() {
        func isVisible(_ layout: BubbleLayout) -> Bool? {
            layout.tokens.first { $0.token == .model }?.isVisible
        }
        XCTAssertEqual(isVisible(.original), false)
        XCTAssertEqual(isVisible(.standard), false)
        XCTAssertEqual(isVisible(.detailed), true)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter BubbleSettingsTests`
Expected: FAIL — compile error, `.model` is not a member of `BubbleToken`.

- [ ] **Step 3: Add `.model` case to `BubbleToken`**

In `Sources/App/BubbleSettings.swift`, update the `BubbleToken` enum. Replace the whole enum (from `enum BubbleToken: String, CaseIterable, Codable, Identifiable {` through its closing `}`) with:

```swift
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
```

- [ ] **Step 4: Add `.model` to the layout presets**

In the same file, update `BubbleLayout`'s three static presets. Replace `static let original`, `static let standard`, and `static let detailed` with:

```swift
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
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --filter BubbleSettingsTests`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/App/BubbleSettings.swift Tests/DesktopPetAppTests/BubbleSettingsTests.swift
git commit -m "feat: add Model bubble token and layout presets"
```

---

### Task 6: Render the model token in `AgentRow`

**Files:**
- Modify: `Sources/App/PetView.swift`

- [ ] **Step 1: Update `tokenHasValue`**

In `Sources/App/PetView.swift`, find `private func tokenHasValue(_ token: BubbleToken) -> Bool` (around line 782) and replace it with:

```swift
    private func tokenHasValue(_ token: BubbleToken) -> Bool {
        if token == .title { return session.title != nil }
        if token == .model { return session.model != nil }
        return true
    }
```

- [ ] **Step 2: Add the `.model` case to `tokenView(for:)`**

In the same file, find the `switch token` inside `tokenView(for:)` (around line 726). Add a new case right after the `.stateLabel` case (around line 769, after its closing brace and before `case .elapsed:`):

```swift
        case .model:
            if let model = session.model {
                Text(model)
                    .font(.system(size: secondaryPt, weight: .regular))
                    .foregroundStyle(textColor(0.55))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add Sources/App/PetView.swift
git commit -m "feat: render model token in agent bubble row"
```

---

### Task 7: Full test suite + manual check

**Files:** none (verification only)

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: All tests PASS, including all new tests from Tasks 1–5.

- [ ] **Step 2: Manual check — enable the Model token**

Run the app (`swift run desktoppet` or via Xcode), open Settings → Bubble layout, switch to the "Detailed" preset (or use "+ Model" in the inactive-tokens picker on Original/Standard), and start a real Claude Code session in a hooked project.

Expected: the bubble row shows a small "Sonnet 4.6" (or whatever the current model's `display_name` is) next to the other tokens. If a Cursor/Codex/etc. session is also running, its row either shows its own model name or simply omits the token — neither should break the row layout.

- [ ] **Step 3: No commit needed for this task** (verification only — if Step 2 reveals issues, fix and commit as part of the relevant earlier task).

---

## Spec coverage check

- §1 `HookModelInfo` decoder → Task 1
- §2 `AgentEvent.model` → Task 1
- §3 per-payload decode (Claude/Codex/Gemini/opencode/Copilot/Kiro via `ClaudeHookPayload`; Cursor/Windsurf/Antigravity) → Tasks 2–3
- §4 `AgentSession.model` → Task 4
- §5 `SessionStore.apply` sticky merge → Task 4
- §6 `BubbleToken.model` + layout presets → Task 5
- §7 `AgentRow` rendering → Task 6
- Testing section → covered across Tasks 1–5 plus manual check in Task 7
