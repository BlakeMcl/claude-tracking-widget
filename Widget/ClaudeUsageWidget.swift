import WidgetKit
import SwiftUI
import Charts
import ClaudeUsageCore

// MARK: - Data

enum Loaded {
    case snapshot(UsageSnapshot)
    case missing
}

struct UsageEntry: TimelineEntry {
    let date: Date
    let state: Loaded
}

/// The sandboxed widget's home directory is its container, so resolve the real one.
private func snapshotURL() -> URL {
    if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
        return URL(fileURLWithPath: String(cString: dir))
            .appendingPathComponent("Library/Application Support/ClaudeUsageWidget/snapshot.json")
    }
    return UsageSnapshot.defaultURL()
}

private func load() -> Loaded {
    if let s = UsageSnapshot.load(from: snapshotURL()) { return .snapshot(s) }
    return .missing
}

private let sample: UsageSnapshot = {
    let cal = Calendar.current
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    var days: [UsageSnapshot.DayTokens] = []
    for i in 0..<7 {
        let d = cal.date(byAdding: .day, value: i - 6, to: Date())!
        let input: Int = 1_000 * (i + 2)
        let output: Int = 8_000 * (i + 1)
        let cacheRead: Int = 300_000 + 40_000 * i
        days.append(UsageSnapshot.DayTokens(day: f.string(from: d), input: input, output: output,
                                            cacheRead: cacheRead, cacheWrite: 30_000))
    }
    let five = UsageSnapshot.LimitWindow(label: "5h", percentUsed: 42, resetsAt: Date().addingTimeInterval(7_200))
    let week = UsageSnapshot.LimitWindow(label: "Week", percentUsed: 71, resetsAt: Date().addingTimeInterval(200_000))
    let ctx = UsageSnapshot.ContextUsage(percentUsed: 38, tokensUsed: 76_000, windowSize: 200_000)
    return UsageSnapshot(limits: [five, week], days: days, context: ctx)
}()

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry { .init(date: Date(), state: .snapshot(sample)) }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        completion(.init(date: Date(), state: context.isPreview ? .snapshot(sample) : load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        completion(Timeline(entries: [.init(date: now, state: load())],
                            policy: .after(now.addingTimeInterval(5 * 60))))
    }
}

// MARK: - Helpers

private let staleAfter: TimeInterval = 10 * 60

private func limitColor(_ pct: Double) -> Color {
    pct >= 85 ? .red : pct >= 60 ? .orange : .accentColor
}

private func compact(_ n: Int) -> String {
    n >= 1_000_000 ? String(format: "%.1fM", Double(n) / 1e6) : n >= 1_000 ? String(format: "%.0fk", Double(n) / 1e3) : "\(n)"
}

private func costSuffix(_ usd: Double?) -> String {
    usd.map { " · ~\(UsageSnapshot.formatCost($0))" } ?? ""
}

// MARK: - Views

struct LimitRing: View {
    let limit: UsageSnapshot.LimitWindow?
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle().stroke(.secondary.opacity(0.2), lineWidth: 8)
                if let l = limit {
                    Circle().trim(from: 0, to: min(l.percentUsed, 100) / 100)
                        .stroke(limitColor(l.percentUsed), style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text("\(Int(l.percentUsed))%").font(.system(.body, design: .rounded).bold())
                } else {
                    Text("–").foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            Text(label).font(.caption2.bold())
            if let r = limit?.resetsAt, r > Date() {
                Text(r, style: .relative).font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            } else if limit == nil {
                Text("unavailable").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

struct ContextBar: View {
    let context: UsageSnapshot.ContextUsage?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("Context").font(.caption.bold())
                Spacer()
                Text(context.map { "\(Int($0.percentUsed))%" } ?? "unavailable")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: min(context?.percentUsed ?? 0, 100), total: 100)
                .tint(limitColor(context?.percentUsed ?? 0))
        }
    }
}

struct TokenChart: View {
    let days: [UsageSnapshot.DayTokens]
    var body: some View {
        Chart {
            ForEach(days.suffix(7), id: \.day) { d in
                BarMark(x: .value("Day", String(d.day.suffix(5))), y: .value("Tokens", d.total))
                    .foregroundStyle(Color.accentColor.gradient)
            }
        }
        .chartYAxis { AxisMarks { v in AxisValueLabel { if let n = v.as(Int.self) { Text(compact(n)) } } } }
    }
}

struct StaleFooter: View {
    let updated: Date
    var body: some View {
        if Date().timeIntervalSince(updated) > staleAfter {
            Text("Updated ").font(.caption2).foregroundStyle(.secondary)
            + Text(updated, style: .relative).font(.caption2).foregroundStyle(.secondary)
            + Text(" ago").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct EntryView: View {
    @Environment(\.widgetFamily) var family
    let entry: UsageEntry

    var body: some View {
        switch entry.state {
        case .missing:
            VStack(spacing: 6) {
                Image(systemName: "gauge.with.dots.needle.0percent").font(.title)
                Text("No data yet").font(.headline)
                Text("Launch Claude Usage Host to start collecting.")
                    .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
        case .snapshot(let s):
            let stale = Date().timeIntervalSince(s.updatedAt) > staleAfter
            let five = s.limits.first { $0.label.lowercased().contains("5") || $0.label.lowercased().contains("five") } ?? s.limits.first
            let week = s.limits.first { $0.label.lowercased().contains("week") || $0.label.lowercased().contains("7") }
            let today = s.days.last
            Group {
                switch family {
                case .systemSmall:
                    HStack(spacing: 10) {
                        LimitRing(limit: five, label: "5h")
                        LimitRing(limit: week, label: "Week")
                    }
                case .systemMedium:
                    VStack(spacing: 8) {
                        HStack { Spacer(); LimitRing(limit: five, label: "5-hour"); Spacer()
                                 LimitRing(limit: week, label: "Weekly"); Spacer() }
                        ContextBar(context: s.context)
                        if let t = today {
                            Text("Today \(compact(t.total)) tokens\(costSuffix(t.costUSD))")
                                .font(.caption.bold())
                        }
                        StaleFooter(updated: s.updatedAt)
                    }
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack { Spacer(); LimitRing(limit: five, label: "5-hour"); Spacer()
                                 LimitRing(limit: week, label: "Weekly"); Spacer() }
                        ContextBar(context: s.context)
                        if let t = today {
                            Text("Today: \(compact(t.total)) tokens\(costSuffix(t.costUSD))").font(.caption.bold())
                            Text("in \(compact(t.input)) · out \(compact(t.output)) · cache r \(compact(t.cacheRead)) / w \(compact(t.cacheWrite))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        TokenChart(days: s.days)
                        if let w = s.weekCostUSD {
                            Text("7 days: ~\(UsageSnapshot.formatCost(w)) (est. API cost)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        StaleFooter(updated: s.updatedAt)
                    }
                }
            }
            .opacity(stale ? 0.55 : 1)
        }
    }
}

// MARK: - Widget

@main
struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: Provider()) { entry in
            EntryView(entry: entry)
                .containerBackground(.background, for: .widget)
                .widgetURL(URL(string: "claude://"))
        }
        .configurationDisplayName("Claude Usage")
        .description("Plan limits, context and daily tokens for Claude Code.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
