# Claude Usage macOS Widget — Implementation Plan

## Goal
A macOS desktop/Notification Center widget (WidgetKit, SwiftUI) that shows Claude usage at a glance:
1. **Plan limits**: 5-hour and weekly % used, with time until reset.
2. **Token counts**: daily tokens from Claude Code (last 7–14 days).
3. **Context usage**: context-window fill for the active Claude Code session.

Target: macOS 14+, Xcode 27 (installed). Mac only for v1. iOS sync is out of scope (would need CloudKit and a paid developer account).

## Architecture

```
Claude Code ──statusline JSON──▶ claude-usage-collector ──▶ snapshot.json ──▶ Widget (reads)
~/.claude/projects/*.jsonl ─────▶ (LogScanner)                  ▲
                                                         Host app (refresh + reload timelines)
```

- The widget is **sandboxed** and cannot read `~/.claude`. A non-sandboxed collector (CLI and/or host app) gathers data and writes a single `snapshot.json`.
- The widget only reads `snapshot.json`, from a shared **App Group** container in the final build. During development it reads `~/Library/Application Support/ClaudeUsageWidget/snapshot.json`.

## Data sources and known limits
| Data | Source | Reliability |
|---|---|---|
| Daily tokens | `~/.claude/projects/**/*.jsonl` → `message.usage` (input, output, cache read/write). De-duped by `message.id` + `requestId`. | Good, but **Claude Code only**. Desktop chat is not logged locally. |
| 5h / weekly limits | Claude Code **statusline** stdin JSON (`rate_limits.five_hour`, `seven_day`) | **Unverified** for the user's version (2.1.278). First task is to capture a real payload. No official API exists; do not scrape claude.ai. |
| Context % | Statusline JSON `context_window` | Same caveat. |

Fallback if statusline lacks `rate_limits`: widget shows tokens and context only, and limit rings render an "unavailable" state. Do not fabricate numbers.

## Status
Done (in this folder, untested because the Xcode license was not yet accepted):
- `Package.swift`: `ClaudeUsageCore` library, `claude-usage-collector` executable, tests.
- `Snapshot.swift`: `UsageSnapshot` model and JSON load/write (ISO8601 dates).
- `LogScanner.swift`: log aggregation with de-dupe.
- `StatuslineIngest.swift`: tolerant statusline parser.
- `claude-usage-collector/main.swift`: modes `scan` and `statusline`.
- `CoreTests.swift`: parsing and de-dupe tests.

## Steps

### 0. Prerequisites
- [ ] `sudo xcodebuild -license accept` (needs the user's password).
- [ ] Optional: `brew install xcodegen` to generate the `.xcodeproj` from a spec (otherwise create it in Xcode by hand).

### 1. Verify the core
- [ ] `swift test` passes.
- [ ] `swift run claude-usage-collector scan` writes `snapshot.json`. Spot-check today's total against a manual `jq` sum of the logs.
- [ ] Confirm the timezone and day bucketing are correct.

### 2. Statusline hook (limits and context)
- [ ] Add a temporary statusline that dumps stdin to a file (`tee /tmp/statusline.json`) and inspect the real payload.
- [ ] Adjust `StatuslineIngest` field names to match (`used_percentage`, `resets_at` units, context fields).
- [ ] Point the `statusLine` setting in `~/.claude/settings.json` at the built `claude-usage-collector statusline` binary (copy it to a stable path, e.g. `~/.local/bin`).
- [ ] Note: the statusline only updates while Claude Code is active, so mark data stale after N minutes in the UI.
- [ ] Add a test using the captured payload as a fixture.

### 3. Xcode project
Targets:
- **ClaudeUsageHost** (macOS app, non-sandboxed): menu-bar or minimal window, runs `LogScanner` on a timer (every 60s), writes `snapshot.json`, calls `WidgetCenter.shared.reloadAllTimelines()`. Optionally a login item so it runs at startup.
- **ClaudeUsageWidget** (Widget Extension, sandboxed): reads `snapshot.json`.
- Link `ClaudeUsageCore` (local package) into both.
- Enable the **App Groups** capability on both (`group.<teamid>.claudeusage`). Move the snapshot path into the group container. Sign with a free personal team for local use.

### 4. Widget UI (SwiftUI)
- `TimelineProvider`: entry every 5 min, plus reload on host-app writes.
- **Small**: 5h ring and weekly % with reset countdown (`Text(date, style: .relative)`).
- **Medium**: two limit rings and a context bar.
- **Large**: adds a 7-day token bar chart (Swift Charts) with today's input, output and cache breakdown.
- States: loading, no data (setup hint), stale (greyed with "updated Xm ago"), limits unavailable.
- Colours: neutral to amber to red at 60% and 85%. Support light and dark.
- Placeholder and snapshot entries for the widget gallery.

### 5. Polish
- [ ] Tap-through (`widgetURL`) opens the Claude app.
- [ ] README: install steps, statusline setup, troubleshooting.
- [ ] Handle a missing or corrupt `snapshot.json` without crashing.
- [ ] Performance: scanning large log dirs. Skip files older than the cutoff (already done) and consider an incremental cache by file mtime and offset.

## Acceptance criteria
- Adding the widget to the desktop shows real numbers within 2 minutes of launching the host app.
- Limit percentages match the usage shown in the Claude app (±1%).
- Token totals match a manual log sum.
- No credentials are read or stored. The widget makes no network calls.

## Risks
- Statusline schema is not a stable public contract. Keep parsing defensive and fixture-tested.
- Free-tier signing and App Groups on macOS can be finicky. Fall back to a non-sandboxed widget path or a shared file in a user-readable location if needed.
- Claude desktop chat usage is invisible to this approach.
