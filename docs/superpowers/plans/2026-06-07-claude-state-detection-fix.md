# Claude State-Detection Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop DesktopPet from wrongly reporting Claude sessions as "Done" when they're actually waiting on the user (and from flickering done↔working when a subagent finishes mid-task).

**Architecture:** Two `StateMapper` mappings are wrong for Claude: `SubagentStop` shouldn't change session state at all (it fires mid-task, not at session end), and `Stop` always means "done" even when Claude ended its turn by asking the user a question. Fix #1 is a one-line mapping change. Fix #2 needs a small pure `QuestionDetector` unit, a new transcript-reading helper, a race-safe `SessionStore.refineState` correction method, and an `AppDaemon` flow that holds the done/waiting notification until an async transcript check resolves — then fires exactly one notification reflecting the true final state.

**Tech Stack:** Swift 6, XCTest, `@testable import DesktopPetCore`

---

## File Structure

- Modify: `Sources/DesktopPetCore/StateMapper.swift` — drop the `SubagentStop → .done` mapping
- Create: `Sources/DesktopPetCore/QuestionDetector.swift` — pure text heuristic, no I/O
- Modify: `Sources/DesktopPetCore/TranscriptReader.swift` — add `latestAssistantText(at:)`
- Modify: `Sources/DesktopPetCore/SessionStore.swift` — add `refineState(id:from:to:since:)`
- Modify: `Sources/App/AppDaemon.swift` — hold-and-fire-once flow for Claude `Stop → .done`
- Test: `Tests/DesktopPetCoreTests/SessionStoreTests.swift` — `StateMapperTests` + `SessionStoreTests` updates
- Test: `Tests/DesktopPetCoreTests/QuestionDetectorTests.swift` — new
- Test: `Tests/DesktopPetCoreTests/TranscriptReaderLatestAssistantTextTests.swift` — new

---

## Task 1: Stop mapping `SubagentStop` to `.done`

**Files:**
- Modify: `Sources/DesktopPetCore/StateMapper.swift:30`
- Test: `Tests/DesktopPetCoreTests/SessionStoreTests.swift:12` (existing `testClaudeEventMapping`)

- [ ] **Step 1: Update the existing test to expect `nil`**

In `Tests/DesktopPetCoreTests/SessionStoreTests.swift`, find this line inside `testClaudeEventMapping` (around line 12):

```swift
        XCTAssertEqual(StateMapper.state(for: .claude, eventName: "SubagentStop"), .done)
```

Replace it with:

```swift
        XCTAssertNil(StateMapper.state(for: .claude, eventName: "SubagentStop"),
                     "a subagent finishing mid-task must not change the main session's state")
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter StateMapperTests/testClaudeEventMapping -v`
Expected: FAIL — `XCTAssertNil failed: "done"` (current mapping still returns `.done`)

- [ ] **Step 3: Fix the mapping**

In `Sources/DesktopPetCore/StateMapper.swift`, the Claude case currently reads (around line 25-32):

```swift
        case .claude:
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
            case "Notification": return .waiting
            case "Stop", "SubagentStop": return .done
            default: return nil
            }
```

Change it to:

```swift
        case .claude:
            switch eventName {
            case "SessionStart": return .registered
            case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .working
            case "Notification": return .waiting
            case "Stop": return .done
            // SubagentStop fires when a Task() subagent finishes mid-session —
            // not when the main session is done. Ignoring it (nil = "no state
            // change") avoids a false done→working flicker.
            case "SubagentStop": return nil
            default: return nil
            }
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `swift test --filter StateMapperTests/testClaudeEventMapping -v`
Expected: PASS

- [ ] **Step 5: Check the hook-coverage test still passes**

`testHookSpecsCoverInstallEvents` (in the same file) asserts every registered hook event maps to a non-nil state unless it's a session-end event. `SubagentStop` is registered for Claude (`AgentHooks.swift:35`) and is *not* a session-end event, so this assertion would now fail for it. Run:

Run: `swift test --filter StateMapperTests/testHookSpecsCoverInstallEvents -v`
Expected: FAIL — `XCTAssertNotNil failed - claude SubagentStop`

This is expected: the test's premise ("every registered event must map to a state") is no longer true now that we're intentionally ignoring one. Update the test to allow a documented exception. Find this in the same file:

```swift
    func testHookSpecsCoverInstallEvents() {
        // Every event we register must either map to a state or end the session.
        for kind in [AgentKind.claude, .codex, .gemini] {
            let spec = AgentHooks.spec(for: kind)!
            for event in spec.events where !StateMapper.isSessionEnd(for: kind, eventName: event) {
                XCTAssertNotNil(StateMapper.state(for: kind, eventName: event), "\(kind) \(event)")
            }
        }
    }
```

Replace it with:

```swift
    func testHookSpecsCoverInstallEvents() {
        // Every event we register must either map to a state, end the session,
        // or be an intentionally-ignored event (documented here).
        let intentionallyIgnored: [AgentKind: Set<String>] = [
            .claude: ["SubagentStop"]
        ]
        for kind in [AgentKind.claude, .codex, .gemini] {
            let spec = AgentHooks.spec(for: kind)!
            let ignored = intentionallyIgnored[kind] ?? []
            for event in spec.events
            where !StateMapper.isSessionEnd(for: kind, eventName: event) && !ignored.contains(event) {
                XCTAssertNotNil(StateMapper.state(for: kind, eventName: event), "\(kind) \(event)")
            }
        }
    }
```

- [ ] **Step 6: Run the full StateMapper test suite**

Run: `swift test --filter StateMapperTests -v`
Expected: PASS — all tests green

- [ ] **Step 7: Commit**

```bash
git add Sources/DesktopPetCore/StateMapper.swift Tests/DesktopPetCoreTests/SessionStoreTests.swift
git commit -m "fix(core): ignore SubagentStop instead of marking the session done

A Task() subagent finishing mid-session isn't the main session finishing —
the main loop resumes right after, producing a false done→working flicker.
Map it to nil (no state change) like other irrelevant events."
```

---

## Task 2: `QuestionDetector` — pure question-phrase heuristic

**Files:**
- Create: `Sources/DesktopPetCore/QuestionDetector.swift`
- Test: `Tests/DesktopPetCoreTests/QuestionDetectorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DesktopPetCoreTests/QuestionDetectorTests.swift`:

```swift
import XCTest
@testable import DesktopPetCore

final class QuestionDetectorTests: XCTestCase {
    func testEndsWithQuestionMark() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion("Which approach do you prefer, A or B?"))
    }

    func testTrailingWhitespaceAfterQuestionMarkStillDetected() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion("Want me to push this too?  \n"))
    }

    func testRequestForDirectionPhraseWithoutQuestionMark() {
        XCTAssertTrue(QuestionDetector.looksLikeQuestion(
            "I've made the change. Let me know if you'd like any tweaks."))
        XCTAssertTrue(QuestionDetector.looksLikeQuestion(
            "Should I go ahead and run the migration now"))
    }

    func testPlainCompletionStatementIsNotAQuestion() {
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(
            "Done — fixed the login bug and added a regression test."))
    }

    func testEmptyAndWhitespaceOnlyAreNotQuestions() {
        XCTAssertFalse(QuestionDetector.looksLikeQuestion(""))
        XCTAssertFalse(QuestionDetector.looksLikeQuestion("   \n  "))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter QuestionDetectorTests -v`
Expected: FAIL — `cannot find 'QuestionDetector' in scope`

- [ ] **Step 3: Implement `QuestionDetector`**

Create `Sources/DesktopPetCore/QuestionDetector.swift`:

```swift
import Foundation

/// Detects whether a piece of assistant text reads like Claude ended its turn
/// by asking the user something — as opposed to simply reporting completion.
///
/// Pure string logic: no I/O, no actor isolation. Used to correct a session's
/// state from `.done` to `.waiting` when Claude's `Stop` hook fires after a
/// turn that actually ended in a question (Claude Code sends no separate event
/// for "I asked the user something and am waiting for a reply").
public enum QuestionDetector {
    private static let directionPhrases = [
        "let me know",
        "should i",
        "which would you",
        "do you want",
        "want me to",
        "shall i",
        "would you like"
    ]

    /// True if `text` looks like a request for the user's direction: it ends
    /// with a question mark, or contains a recognizable "asking what to do
    /// next" phrase.
    public static func looksLikeQuestion(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasSuffix("?") { return true }
        let lowered = trimmed.lowercased()
        return directionPhrases.contains { lowered.contains($0) }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter QuestionDetectorTests -v`
Expected: PASS — all 5 tests green

- [ ] **Step 5: Commit**

```bash
git add Sources/DesktopPetCore/QuestionDetector.swift Tests/DesktopPetCoreTests/QuestionDetectorTests.swift
git commit -m "feat(core): add QuestionDetector heuristic for turn-ending questions

Pure text check used to tell 'Claude is truly done' apart from 'Claude
ended its turn by asking the user something' — Stop fires identically
for both, so DesktopPet needs its own signal."
```

---

## Task 3: `TranscriptReader.latestAssistantText` — raw last-assistant-message text

**Files:**
- Modify: `Sources/DesktopPetCore/TranscriptReader.swift`
- Test: `Tests/DesktopPetCoreTests/TranscriptReaderLatestAssistantTextTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/DesktopPetCoreTests/TranscriptReaderLatestAssistantTextTests.swift`:

```swift
import XCTest
@testable import DesktopPetCore

final class TranscriptReaderLatestAssistantTextTests: XCTestCase {
    private func tempTranscript(_ lines: [String]) throws -> String {
        let path = NSTemporaryDirectory() + "transcript-\(UUID().uuidString).jsonl"
        try Data(lines.joined(separator: "\n").utf8).write(to: URL(fileURLWithPath: path))
        return path
    }

    private func assistantLine(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\"", with: "\\\"")
        return #"{"type":"assistant","message":{"content":[{"type":"text","text":"\#(escaped)"}]}}"#
    }

    private let userLine = #"{"type":"user","message":{"content":[{"type":"text","text":"thanks"}]}}"#

    func testReturnsLatestAssistantTextVerbatim() throws {
        let path = try tempTranscript([
            assistantLine("Working on it now."),
            userLine,
            assistantLine("Which approach do you want — A or B?")
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(TranscriptReader.latestAssistantText(at: path),
                       "Which approach do you want — A or B?")
    }

    func testSkipsTrailingNonAssistantLines() throws {
        let path = try tempTranscript([
            assistantLine("All done — pushed the fix."),
            userLine
        ])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertEqual(TranscriptReader.latestAssistantText(at: path),
                       "All done — pushed the fix.")
    }

    func testReturnsNilForUnreadablePath() {
        XCTAssertNil(TranscriptReader.latestAssistantText(at: "/no/such/file-\(UUID().uuidString).jsonl"))
    }

    func testReturnsNilWhenNoAssistantLineExists() throws {
        let path = try tempTranscript([userLine])
        defer { try? FileManager.default.removeItem(atPath: path) }

        XCTAssertNil(TranscriptReader.latestAssistantText(at: path))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter TranscriptReaderLatestAssistantTextTests -v`
Expected: FAIL — `value of type 'TranscriptReader.Type' has no member 'latestAssistantText'`

- [ ] **Step 3: Implement `latestAssistantText`**

In `Sources/DesktopPetCore/TranscriptReader.swift`, add this new public function. Place it directly after `latestAssistantRecap` (after line 37, before the `clearCache` method):

```swift
    /// Returns the raw, trimmed text of the most recent Claude assistant
    /// message in the transcript (capped at 400 characters), or `nil` if none
    /// is found. Unlike `latestAssistantRecap`, this returns ordinary
    /// turn-ending text too — it's used to check whether Claude ended its
    /// turn by asking the user a question, not to extract a named recap.
    public static func latestAssistantText(at path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let maxBytes: UInt64 = 131_072
        try? handle.seek(toOffset: fileSize > maxBytes ? fileSize - maxBytes : 0)
        let raw = handle.readDataToEndOfFile()
        guard let text = String(data: raw, encoding: .utf8) else { return nil }

        for line in text.components(separatedBy: "\n").reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  let lineData = trimmed.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let assistantText = extractAssistantText(from: json)
            else { continue }
            return String(assistantText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(400))
        }

        return nil
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter TranscriptReaderLatestAssistantTextTests -v`
Expected: PASS — all 4 tests green

- [ ] **Step 5: Commit**

```bash
git add Sources/DesktopPetCore/TranscriptReader.swift Tests/DesktopPetCoreTests/TranscriptReaderLatestAssistantTextTests.swift
git commit -m "feat(core): add TranscriptReader.latestAssistantText

Raw last-assistant-message text (no recap-marker filtering), used by the
done/waiting question heuristic to inspect how Claude ended its turn."
```

---

## Task 4: `SessionStore.refineState` — race-safe done→waiting correction

**Files:**
- Modify: `Sources/DesktopPetCore/SessionStore.swift`
- Test: `Tests/DesktopPetCoreTests/SessionStoreTests.swift`

- [ ] **Step 1: Write the failing tests**

In `Tests/DesktopPetCoreTests/SessionStoreTests.swift`, add these three tests inside `final class SessionStoreTests` (e.g. directly after `testApplyIgnoresUnmappedEvent`, around line 80):

```swift
    func testRefineStateAppliesWhenStateAndSinceStillMatch() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        XCTAssertEqual(applied?.state, .done)

        store.refineState(id: "s1", from: .done, to: .waiting, since: applied!.stateSince)

        let refined = store.session(id: "s1")
        XCTAssertEqual(refined?.state, .waiting)
        XCTAssertEqual(refined?.stateSince, applied!.stateSince,
                       "correction preserves the original transition time")
    }

    func testRefineStateNoOpsWhenANewerEventAlreadyChangedState() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        store.apply(event("UserPromptSubmit"), now: t0.addingTimeInterval(2))   // user replied -> working

        store.refineState(id: "s1", from: .done, to: .waiting, since: applied!.stateSince)

        XCTAssertEqual(store.session(id: "s1")?.state, .working,
                       "a newer transition must never be clobbered by a stale correction")
    }

    func testRefineStateNoOpsWhenSinceNoLongerMatches() {
        let store = SessionStore()
        let applied = store.apply(event("Stop"), now: t0)
        let staleSince = applied!.stateSince.addingTimeInterval(-10)

        store.refineState(id: "s1", from: .done, to: .waiting, since: staleSince)

        XCTAssertEqual(store.session(id: "s1")?.state, .done,
                       "a `since` mismatch means this correction targets a transition that's gone")
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SessionStoreTests/testRefineState -v`
Expected: FAIL — `value of type 'SessionStore' has no member 'refineState'`

- [ ] **Step 3: Implement `refineState`**

In `Sources/DesktopPetCore/SessionStore.swift`, add this method directly after `updateTitle` (after line 48, before `apply`):

```swift
    /// Corrects a session's state after the fact — used when an async check
    /// (e.g. reading the transcript to see how Claude ended its turn)
    /// determines the state we set synchronously was wrong.
    ///
    /// Only applies when the session is *still* in `expected` state from the
    /// *same* transition (`since` matches `stateSince`): if a newer event has
    /// already moved the session on, this is a no-op — the correction targets
    /// a transition that no longer exists, and must never clobber fresher
    /// state. `stateSince` is preserved (this corrects the existing
    /// transition; it isn't a new one).
    public func refineState(id: String, from expected: AgentState, to refined: AgentState, since: Date) {
        guard var session = byID[id], session.state == expected, session.stateSince == since else { return }
        session.state = refined
        byID[id] = session
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SessionStoreTests/testRefineState -v`
Expected: PASS — all 3 tests green

- [ ] **Step 5: Run the full SessionStore suite to confirm no regressions**

Run: `swift test --filter SessionStoreTests -v`
Expected: PASS — all tests green

- [ ] **Step 6: Commit**

```bash
git add Sources/DesktopPetCore/SessionStore.swift Tests/DesktopPetCoreTests/SessionStoreTests.swift
git commit -m "feat(core): add SessionStore.refineState for race-safe state correction

Lets an async check (transcript read) correct a synchronously-applied
state without ever clobbering a newer transition — guarded by both the
expected state and its stateSince timestamp."
```

---

## Task 5: `AppDaemon` — hold-and-fire-once for Claude `Stop → .done`

**Files:**
- Modify: `Sources/App/AppDaemon.swift:54-92`

This task wires the previous three units together. There's no existing test
harness for `AppDaemon` (it's a `@MainActor` singleton coupled to sockets and
`NotificationManager`), so this task is verified by building and by the
existing full test suite passing — consistent with how `resolveTitle` (the
pattern this mirrors) is untested today.

- [ ] **Step 1: Replace `ingest` and add the correction helper**

In `Sources/App/AppDaemon.swift`, the current `ingest` (lines 54-61) reads:

```swift
    private func ingest(_ event: AgentEvent) {
        let before = store.session(id: event.sessionId)?.state
        if let updated = store.apply(event, now: Date()) {
            notifyIfNeeded(before: before, session: updated)
            resolveTitle(for: event)
        }
        refresh()
    }
```

Replace it with:

```swift
    private func ingest(_ event: AgentEvent) {
        let before = store.session(id: event.sessionId)?.state
        guard let updated = store.apply(event, now: Date()) else {
            refresh()
            return
        }
        resolveTitle(for: event)

        // Claude's Stop hook fires identically whether the agent is truly
        // done or just ended its turn by asking the user a question — hold
        // the notification until an async transcript check resolves, so we
        // fire exactly one notification reflecting the true final state.
        if event.agentKind == .claude, event.eventName == "Stop", updated.state == .done {
            refineDoneIfQuestion(event: event, before: before, session: updated)
        } else {
            notifyIfNeeded(before: before, session: updated)
        }
        refresh()
    }

    /// Reads the transcript off-thread to check whether Claude ended its turn
    /// by asking the user something; if so, corrects `.done` to `.waiting`.
    /// Either way, fires the (single, final-state) notification afterwards.
    private func refineDoneIfQuestion(event: AgentEvent, before: AgentState?, session: AgentSession) {
        let sessionId = event.sessionId
        let stateSince = session.stateSince
        let path: String? = event.transcriptPath
            ?? event.project.map { TranscriptReader.inferredPath(sessionId: sessionId, cwd: $0) }
        guard let path else {
            notifyIfNeeded(before: before, session: session)
            return
        }
        Task.detached(priority: .utility) { [weak self] in
            let isQuestion = TranscriptReader.latestAssistantText(at: path)
                .map(QuestionDetector.looksLikeQuestion) ?? false
            await MainActor.run { [weak self] in
                guard let self else { return }
                if isQuestion {
                    self.store.refineState(id: sessionId, from: .done, to: .waiting, since: stateSince)
                }
                guard let final = self.store.session(id: sessionId) else { return }
                self.notifyIfNeeded(before: before, session: final)
                self.refresh()
            }
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: `Build complete!` with no errors or warnings about the new code

- [ ] **Step 3: Run the full test suite to confirm no regressions**

Run: `swift test 2>&1 | tail -30`
Expected: all suites pass (`Executed N tests, with 0 failures`)

- [ ] **Step 4: Manual smoke check (optional but recommended)**

Launch the app (`swift run desktoppet` or via Xcode), start a Claude Code
session in a watched project, and:
- Ask Claude to do something simple, then have it end by asking you a
  clarifying question (e.g. "implement X, but first ask me which of two
  approaches I'd prefer"). Confirm the bubble shows **Waiting** (not Done)
  and you get exactly one "needs input" notification — not a "finished"
  notification followed by a correction.
- Ask Claude to do something that finishes cleanly with no question.
  Confirm it still shows **Done** promptly with one "finished" notification.
- Trigger a `Task()` subagent (e.g. "use a subagent to look up X, then
  continue working"). Confirm the bubble does *not* flash "Done" when the
  subagent finishes — it should stay "Working".

- [ ] **Step 5: Commit**

```bash
git add Sources/App/AppDaemon.swift
git commit -m "fix(app): correct done->waiting for Claude turns that end in a question

Stop fires identically for 'truly done' and 'ended turn by asking the
user something' — neither DesktopPet nor the hook payload can tell them
apart without reading the transcript. Hold the notification for Claude
Stop->done specifically, check asynchronously, correct if needed, and
fire exactly one notification reflecting the true final state."
```

---

## Self-Review Notes

- **Spec coverage:** Fix 1 (Task 1), `QuestionDetector` (Task 2),
  `latestAssistantText` (Task 3), `refineState` (Task 4), hold-and-fire-once
  `AppDaemon` flow (Task 5) — all five spec sections have a task.
- **No setting added** — matches "Out of scope" in the spec (correctness
  fix, not a preference).
- **Non-Claude agents untouched** — `refineDoneIfQuestion` is gated on
  `event.agentKind == .claude`, so Codex/Gemini/etc. keep firing
  `notifyIfNeeded` immediately as before.
- **Type/signature consistency checked:** `refineState(id:from:to:since:)`
  signature matches between Task 4's implementation and Task 5's call site;
  `QuestionDetector.looksLikeQuestion(_:)` and
  `TranscriptReader.latestAssistantText(at:)` signatures match between their
  Task 2/3 implementations and the Task 5 call site.
