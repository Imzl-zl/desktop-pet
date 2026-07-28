# Fix Claude state-detection: SubagentStop + done/waiting question heuristic

## Problem

`StateMapper` (Sources/DesktopPetCore/StateMapper.swift) maps Claude Code hook
events to `AgentState`, which drives notifications, sounds, pet mood/animation,
and the multi-agent bubble — for *all* users, regardless of which bubble UI
they have enabled. Two mappings are wrong:

1. **`SubagentStop → .done`** — fires when a `Task()` subagent finishes
   mid-session, not when the main session is done. The main loop resumes
   (`PreToolUse`/`PostToolUse`) right after, so this produces a false
   "Done" flash that flips back to "Working" moments later.

2. **`Stop → .done` always** — Claude Code fires `Stop` at the end of *every*
   assistant turn, including turns where Claude ends by asking the user a
   plain-text clarifying question ("Which approach do you want — A or B?").
   No `Notification`/permission event accompanies that. DesktopPet has no
   signal to distinguish "truly done" from "done talking, waiting on your
   reply," so it shows **Done** (and fires a "finished" notification/sound)
   when Claude is actually **waiting for the user**.

This fix applies to the underlying state — and therefore to notifications,
sounds, and pet mood for everyone — not just to the multi-agent bubble
display.

## Fix 1 — Drop `SubagentStop` mapping

`StateMapper.state(for: .claude, eventName: "SubagentStop")` returns `nil`
instead of `.done`. A `nil` result means "ignore this event, don't change
state" (existing behavior for unknown events). One-line change.

## Fix 2 — Detect "ended by asking a question" and correct done → waiting

Claude Code's `Stop` hook payload carries no reply text — only session id and
transcript path. So detection requires reading the transcript file
asynchronously (the same pattern `resolveTitle` already uses for title
resolution) and correcting the state after the fact if needed.

### New unit: `QuestionDetector`

`Sources/DesktopPetCore/QuestionDetector.swift`:

```swift
public enum QuestionDetector {
    /// True if `text` reads like Claude ended its turn by asking the user
    /// something (a question mark, or a request-for-direction phrase).
    public static func looksLikeQuestion(_ text: String) -> Bool
}
```

Pure string logic — trims/lowercases, returns true if the text ends with `?`,
or contains phrases such as "let me know", "should i", "which would you",
"do you want", "want me to", "shall i", "would you like". No I/O, no actor
isolation — independently unit-testable.

### New `TranscriptReader.latestAssistantText(at:)`

Mirrors the tail-scan already in `readLatestAssistantRecap` (scan lines from
the end of the file, find the last `"assistant"` event, extract its text via
the existing `extractAssistantText`) but returns the **raw trimmed text**
without the `cleanRecap` "recap:"/"summary:" marker filter — that filter is
specific to the recap feature and would return `nil` for ordinary turn-ending
messages, which is exactly the case we need to inspect here. Capped at a few
hundred characters — plenty to evaluate the heuristic.

### New `SessionStore.refineState(id:from:to:since:)`

```swift
public func refineState(id: String, from expected: AgentState, to refined: AgentState, since: Date) {
    guard var s = byID[id], s.state == expected, s.stateSince == since else { return }
    s.state = refined
    byID[id] = s
}
```

The `expected`/`since` guards make this race-safe: if a newer event (e.g. the
user already replied, triggering `UserPromptSubmit → .working`) landed before
the async check resolves, the correction is silently skipped — it never
clobbers fresher state. `stateSince` is preserved (this is a correction of the
existing transition, not a new one), so elapsed-time display stays accurate.

### `AppDaemon` flow — hold-and-fire-once notification

In `ingest`, when the event is Claude's `Stop` and the resulting state is
`.done`:

- Apply the state immediately as today — the UI shows "Done" right away (fast
  feedback for the common, correct case).
- Skip the immediate `notifyIfNeeded` call for *this* transition only.
- Launch `Task.detached(priority: .utility)`: read `latestAssistantText`,
  run `QuestionDetector.looksLikeQuestion`. If it matches, call
  `store.refineState(id:from: .done, to: .waiting, since:)`. Either way, then
  call `notifyIfNeeded(before:, session:)` on the main actor with the
  *final* (possibly corrected) session — exactly one notification/sound is
  fired, reflecting the true final state.
- All other transitions (including non-Claude agents, and Claude transitions
  to `.working`/`.waiting`/`.registered`) keep firing `notifyIfNeeded`
  immediately — unchanged.

## Testing

- `QuestionDetector` — pure unit tests covering question marks, phrase
  patterns, plain statements (no false positive), and edge cases (empty
  string, trailing whitespace/punctuation).
- `SessionStore.refineState` — unit tests: applies when state/since match,
  no-ops when state has moved on, no-ops when `stateSince` has changed
  (i.e. a newer transition superseded it).
- `StateMapper` — test that `SubagentStop` now maps to `nil` for Claude.
- `TranscriptReader.latestAssistantText` — test against fixture transcripts
  (question-ending vs statement-ending last assistant message).

## Out of scope

- No user-facing setting to disable this — it's a correctness fix, not a
  style preference (per discussion).
- No changes to non-Claude agent kinds (Codex, Gemini, etc.) — they don't
  send `Stop`/`SubagentStop` with the same semantics, and don't have a
  transcript reader.
