import Foundation

/// Sums per-day token usage from Claude Code session logs (~/.claude/projects/**/*.jsonl).
public enum LogScanner {
    public static func defaultRoot() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects")
    }

    public static func scan(root: URL = defaultRoot(), days: Int = 14, now: Date = Date(),
                            calendar: Calendar = .current) -> [UsageSnapshot.DayTokens] {
        let cutoff = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        let dayFmt = DateFormatter(); dayFmt.calendar = calendar; dayFmt.dateFormat = "yyyy-MM-dd"
        let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()

        var buckets: [String: UsageSnapshot.DayTokens] = [:]
        var seen = Set<String>()

        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }
        for case let url as URL in en where url.pathExtension == "jsonl" {
            if let m = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate, m < cutoff { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n") where line.contains("\"usage\"") {
                guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let msg = obj["message"] as? [String: Any],
                      let usage = msg["usage"] as? [String: Any],
                      let ts = obj["timestamp"] as? String,
                      let date = iso.date(from: ts) ?? isoPlain.date(from: ts), date >= cutoff else { continue }
                // A message can be logged on several lines; count each (message, request) once.
                if let mid = msg["id"] as? String {
                    let key = mid + "|" + (obj["requestId"] as? String ?? "")
                    if !seen.insert(key).inserted { continue }
                }
                let day = dayFmt.string(from: date)
                var b = buckets[day] ?? .init(day: day, input: 0, output: 0, cacheRead: 0, cacheWrite: 0)
                let input = usage["input_tokens"] as? Int ?? 0
                let output = usage["output_tokens"] as? Int ?? 0
                let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
                let cacheWrite = usage["cache_creation_input_tokens"] as? Int ?? 0
                b.input += input; b.output += output; b.cacheRead += cacheRead; b.cacheWrite += cacheWrite
                if let model = msg["model"] as? String,
                   let c = Pricing.cost(model: model, input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite) {
                    b.costUSD = (b.costUSD ?? 0) + c
                }
                buckets[day] = b
            }
        }
        return buckets.values.sorted { $0.day < $1.day }
    }
}
