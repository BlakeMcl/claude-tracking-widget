import Foundation

/// Everything the widget renders. Written by the collector, read by the widget.
public struct UsageSnapshot: Codable, Equatable {
    public struct LimitWindow: Codable, Equatable {
        public var label: String
        public var percentUsed: Double
        public var resetsAt: Date?
        public init(label: String, percentUsed: Double, resetsAt: Date? = nil) {
            self.label = label; self.percentUsed = percentUsed; self.resetsAt = resetsAt
        }
    }
    public struct DayTokens: Codable, Equatable {
        public var day: String // yyyy-MM-dd, local time
        public var input: Int
        public var output: Int
        public var cacheRead: Int
        public var cacheWrite: Int
        /// Estimated API-equivalent cost in USD (nil in snapshots written before cost tracking).
        public var costUSD: Double?
        public var total: Int { input + output + cacheRead + cacheWrite }
        public init(day: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int, costUSD: Double? = nil) {
            self.day = day; self.input = input; self.output = output
            self.cacheRead = cacheRead; self.cacheWrite = cacheWrite; self.costUSD = costUSD
        }
    }
    public struct ContextUsage: Codable, Equatable {
        public var percentUsed: Double
        public var tokensUsed: Int?
        public var windowSize: Int?
        public init(percentUsed: Double, tokensUsed: Int? = nil, windowSize: Int? = nil) {
            self.percentUsed = percentUsed; self.tokensUsed = tokensUsed; self.windowSize = windowSize
        }
    }

    public var updatedAt: Date
    public var limits: [LimitWindow]
    public var days: [DayTokens]      // most recent last, up to 14 days
    public var context: ContextUsage?

    public init(updatedAt: Date = Date(), limits: [LimitWindow] = [], days: [DayTokens] = [], context: ContextUsage? = nil) {
        self.updatedAt = updatedAt; self.limits = limits; self.days = days; self.context = context
    }

    /// Estimated cost over the last 7 days of `days`, or nil if no day has a cost.
    public var weekCostUSD: Double? {
        let costs = days.suffix(7).compactMap(\.costUSD)
        return costs.isEmpty ? nil : costs.reduce(0, +)
    }

    public static func formatCost(_ usd: Double) -> String {
        usd < 10 ? String(format: "$%.2f", usd) : String(format: "$%.0f", usd)
    }

    public static func defaultURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/ClaudeUsageWidget/snapshot.json")
    }

    public static func load(from url: URL = defaultURL()) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601
        return try? d.decode(UsageSnapshot.self, from: data)
    }

    public func write(to url: URL = defaultURL()) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try e.encode(self).write(to: url, options: .atomic)
    }
}
