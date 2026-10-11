import Foundation

/// Parses the JSON Claude Code pipes to a statusline command and extracts plan limits + context.
/// Field names are read defensively because the schema is not a stable public contract.
public enum StatuslineIngest {
    public static func apply(_ json: Data, to snap: inout UsageSnapshot) {
        guard let root = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return }

        if let rl = root["rate_limits"] as? [String: Any] {
            var limits: [UsageSnapshot.LimitWindow] = []
            for (key, label) in [("five_hour", "5-hour limit"), ("seven_day", "Weekly · all models"),
                                 ("seven_day_opus", "Weekly · Opus"), ("seven_day_sonnet", "Weekly · Sonnet")] {
                guard let w = rl[key] as? [String: Any] else { continue }
                let pct = (w["used_percentage"] as? Double) ?? (w["utilization"] as? Double) ?? 0
                var reset: Date?
                if let secs = w["resets_at"] as? Double { reset = Date(timeIntervalSince1970: secs) }
                else if let s = w["resets_at"] as? String { reset = ISO8601DateFormatter().date(from: s) }
                limits.append(.init(label: label, percentUsed: pct, resetsAt: reset))
            }
            if !limits.isEmpty { snap.limits = limits }
        }

        if let cw = root["context_window"] as? [String: Any] {
            let size = cw["context_window_size"] as? Int
            let pct = (cw["used_percentage"] as? Double)
                ?? ((cw["total_input_tokens"] as? Int).flatMap { used in size.map { Double(used) / Double($0) * 100 } })
            if let pct { snap.context = .init(percentUsed: pct, tokensUsed: cw["total_input_tokens"] as? Int, windowSize: size) }
        }
    }
}
