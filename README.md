# Claude Usage Widget

A macOS widget (WidgetKit + SwiftUI) that shows your Claude Code usage at a glance:

- **Plan limits**: 5-hour and weekly % used, with time until reset
- **Token counts**: daily tokens from Claude Code (last 7–14 days)
- **Context usage**: context-window fill for the active Claude Code session

Mac only, macOS 14+. No network calls, and no credentials are read or stored.

> **Status:** working locally. Token totals, plan limits and context all populate. Still ad-hoc signed, with no App Group. See [PLAN.md](PLAN.md) for remaining work.

## How it works

```
Claude Code ──statusline JSON──▶ claude-usage-collector ──▶ snapshot.json ──▶ Widget (reads)
~/.claude/projects/*.jsonl ─────▶ (LogScanner)                  ▲
                                                         Host app (refresh + reload timelines)
```

The widget is sandboxed and can't read `~/.claude`, so a non-sandboxed collector gathers the data and writes a single `snapshot.json`. During development the file lives at:

```
~/Library/Application Support/ClaudeUsageWidget/snapshot.json
```

The sandboxed widget reads it through a dev-only read-only sandbox exception (`Widget/ClaudeUsageWidget.entitlements`). With a signing team, replace that with an App Group container.

## Requirements

- macOS 14+
- Xcode (the Xcode license must be accepted: `sudo xcodebuild -license accept`)
- Optional: [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) to generate the Xcode project

## Build and test

```sh
swift test
swift run claude-usage-collector scan
```

`scan` reads `~/.claude/projects/**/*.jsonl`, sums `message.usage` per local day (input, output, cache read, cache write, de-duplicated by message id + request id), and writes `snapshot.json`.

Check it:

```sh
jq . ~/Library/Application\ Support/ClaudeUsageWidget/snapshot.json
```

## Build and run the widget

```sh
xcodegen generate          # creates ClaudeUsage.xcodeproj from project.yml
xcodebuild -project ClaudeUsage.xcodeproj -scheme ClaudeUsageHost -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/ClaudeUsageHost.app
```

Or open `ClaudeUsage.xcodeproj` in Xcode and run **ClaudeUsageHost**.

The host app is a menu-bar item. It rescans the logs every 60 seconds, writes `snapshot.json` and reloads widget timelines. Then right-click the desktop, choose **Edit Widgets** and add **Claude Usage** (small, medium or large).

- Tapping the widget opens the Claude desktop app (`claude://`).
- Data older than 10 minutes is dimmed with an "Updated … ago" note.
- The project is ad-hoc signed. If the widget doesn't show in the gallery, set a personal team on both targets in Xcode.

## Statusline setup (limits and context)

Plan limits and context usage come from Claude Code's statusline JSON, which is **not a stable public contract**. The parser (`StatuslineIngest`) is deliberately tolerant. If the fields are missing, the widget shows tokens only and renders the limit rings as "unavailable".

1. Build and copy the collector to a stable path:
   ```sh
   swift build -c release
   mkdir -p ~/.local/bin
   cp .build/release/claude-usage-collector ~/.local/bin/
   ```
2. Point Claude Code at it in `~/.claude/settings.json`:
   ```json
   {
     "statusLine": {
       "type": "command",
       "command": "~/.local/bin/claude-usage-collector statusline"
     }
   }
   ```

This is verified against Claude Code 2.1.296: its payload includes `rate_limits.five_hour` / `seven_day` (`used_percentage`, `resets_at` as epoch seconds) and `context_window` (`used_percentage`, `context_window_size`). A sanitized copy is the test fixture in `Tests/ClaudeUsageCoreTests/Fixtures/`.

To undo, remove the `statusLine` block from `~/.claude/settings.json` and delete `~/.local/bin/claude-usage-collector`.

The statusline only updates while Claude Code is active, so the widget marks data as stale after a few minutes.

## Troubleshooting

- **Limits show as unavailable**: your Claude Code version may not include `rate_limits` in the statusline payload. Capture a payload with a temporary statusline command (`tee /tmp/statusline.json`) and compare field names with `StatuslineIngest.swift`.
- **Token totals look low**: only Claude Code is logged locally. Claude desktop chat usage is not visible to this tool.
- **No snapshot file**: run `swift run claude-usage-collector scan` once.
- **Corrupt snapshot**: delete `snapshot.json`; the next scan recreates it.

## Layout

- `Sources/ClaudeUsageCore/`: snapshot model, log scanner, statusline parser
- `Sources/claude-usage-collector/`: CLI (`scan`, `statusline`)
- `Host/`: menu-bar app that refreshes the snapshot
- `Widget/`: WidgetKit extension (SwiftUI)
- `project.yml`: XcodeGen spec
- `Tests/ClaudeUsageCoreTests/`: parsing, real-payload fixture and de-dupe tests
