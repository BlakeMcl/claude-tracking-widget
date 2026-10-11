import Foundation
import ClaudeUsageCore

// Usage:
//   claude-usage-collector scan                 refresh token counts from ~/.claude/projects
//   claude-usage-collector statusline           read Claude Code statusline JSON on stdin (limits + context),
//                                               refresh token counts, print a one-line status
let mode = CommandLine.arguments.dropFirst().first ?? "scan"
var snap = UsageSnapshot.load() ?? UsageSnapshot()

if mode == "statusline" {
    StatuslineIngest.apply(FileHandle.standardInput.readDataToEndOfFile(), to: &snap)
}
snap.days = LogScanner.scan()
snap.updatedAt = Date()
try snap.write()

if mode == "statusline" {
    let five = snap.limits.first.map { "5h \(Int($0.percentUsed))%" } ?? "5h –"
    let ctx = snap.context.map { "ctx \(Int($0.percentUsed))%" } ?? "ctx –"
    print("\(five) · \(ctx)")
} else {
    let today = snap.days.last
    print("Wrote snapshot. Latest day \(today?.day ?? "-"): \(today?.total ?? 0) tokens")
}
