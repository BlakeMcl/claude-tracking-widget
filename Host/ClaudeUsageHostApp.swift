import SwiftUI
import WidgetKit
import ClaudeUsageCore

@main
struct ClaudeUsageHostApp: App {
    @StateObject private var refresher = Refresher()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(refresher: refresher)
        } label: {
            Text(refresher.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu bar UI

private func color(_ pct: Double) -> Color {
    pct >= 85 ? .red : pct >= 60 ? .orange : .accentColor
}

private func compact(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1_000 ? String(format: "%.0fk", Double(n) / 1e3) : "\(n)"
}

struct UsageRow: View {
    let title: String
    let percent: Double
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.callout.bold())
                Spacer()
                Text("\(Int(percent))%").font(.callout.monospacedDigit())
            }
            ProgressView(value: min(percent, 100), total: 100).tint(color(percent))
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

struct MenuContent: View {
    @ObservedObject var refresher: Refresher

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let s = refresher.snapshot {
                if s.limits.isEmpty {
                    Text("Limits unavailable. Set up the statusline hook (see README).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(s.limits, id: \.label) { l in
                    UsageRow(title: l.label, percent: l.percentUsed, detail: resetText(l.resetsAt))
                }
                if let c = s.context {
                    UsageRow(title: "Context", percent: c.percentUsed,
                             detail: c.tokensUsed.flatMap { used in c.windowSize.map { "\(compact(used)) of \(compact($0)) tokens" } })
                }
                if let t = s.days.last {
                    Divider()
                    Text("Today: \(compact(t.total)) tokens" + (t.costUSD.map { " · ~\(UsageSnapshot.formatCost($0))" } ?? ""))
                        .font(.callout.bold())
                    Text("in \(compact(t.input)) · out \(compact(t.output)) · cache r \(compact(t.cacheRead)) / w \(compact(t.cacheWrite))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let w = s.weekCostUSD {
                    Text("7 days: ~\(UsageSnapshot.formatCost(w)) · estimated at API rates, not billed on a subscription")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Updated \(s.updatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("No data yet").foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Button("Refresh") { refresher.refresh() }
                Button("Open Claude") { NSWorkspace.shared.open(URL(string: "claude://")!) }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func resetText(_ date: Date?) -> String? {
        guard let date, date > Date() else { return nil }
        return "Resets \(date.formatted(.relative(presentation: .named)))"
    }
}

// MARK: - Data

/// Watches the snapshot folder so the menu bar updates as soon as the statusline hook writes.
/// A 60s fallback timer rescans the Claude Code logs (and covers missed file events, e.g. after sleep).
/// Widget reloads are throttled because WidgetKit limits how often timelines may be reloaded.
final class Refresher: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var lastWidgetReload = Date.distantPast
    private var reloadPending = false
    private let minReloadInterval: TimeInterval = 60

    init() {
        refresh()
        startWatching()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Compact bar text, e.g. "6% · 3%". Falls back to "Claude" when limits are unavailable.
    var menuBarTitle: String {
        guard let limits = snapshot?.limits, let first = limits.first else { return "Claude" }
        let rest = limits.dropFirst().first.map { " · \(Int($0.percentUsed))%" } ?? ""
        return "\(Int(first.percentUsed))%\(rest)"
    }

    /// The writer replaces the file atomically, so watch the directory rather than the file.
    private func startWatching() {
        let dir = UsageSnapshot.defaultURL().deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        src.setEventHandler { [weak self] in self?.snapshotChanged() }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    private func snapshotChanged() {
        guard let new = UsageSnapshot.load(), new != snapshot else { return }
        snapshot = new
        requestWidgetReload()
    }

    /// Reload at most once per minute; a change inside the window is applied when it ends.
    private func requestWidgetReload() {
        let wait = minReloadInterval - Date().timeIntervalSince(lastWidgetReload)
        if wait <= 0 {
            lastWidgetReload = Date()
            WidgetCenter.shared.reloadAllTimelines()
        } else if !reloadPending {
            reloadPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
                self?.reloadPending = false
                self?.requestWidgetReload()
            }
        }
    }

    func refresh() {
        DispatchQueue.global(qos: .utility).async {
            // Keep limits/context written by the statusline hook; refresh only the token days.
            var snap = UsageSnapshot.load() ?? UsageSnapshot()
            snap.days = LogScanner.scan()
            snap.updatedAt = Date()
            try? snap.write()
            DispatchQueue.main.async {
                self.snapshot = snap
                self.requestWidgetReload()
            }
        }
    }
}
