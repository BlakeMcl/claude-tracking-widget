import Foundation

/// API list prices in USD per million tokens. Used to estimate what Claude Code usage would cost at API rates;
/// subscription plans are not billed this way. Cache writes are priced at the 5-minute rate (1.25x input).
public enum Pricing {
    public struct Rate {
        public let input: Double, output: Double, cacheRead: Double, cacheWrite: Double
        public init(_ input: Double, _ output: Double, _ cacheRead: Double, _ cacheWrite: Double) {
            self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
        }
    }

    /// Matched by longest model-id prefix, so "claude-opus-5-5" wins over "claude-opus-5".
    static let table: [(prefix: String, rate: Rate)] = [
        ("claude-fable-5", Rate(10, 50, 0.25, 12.5)),
        ("claude-opus-5-5", Rate(4, 20, 0.20, 5)),
        ("claude-opus-5", Rate(5, 25, 0.50, 6.25)),
        ("claude-opus-4", Rate(5, 25, 0.50, 6.25)),
        ("claude-sonnet-5", Rate(2, 10, 0.20, 2.5)),
        ("claude-sonnet-4", Rate(3, 15, 0.30, 3.75)),
        ("claude-haiku-5", Rate(0.10, 0.50, 0.01, 0.125)),
        ("claude-haiku-4", Rate(1, 5, 0.10, 1.25)),
    ]

    public static func rate(for model: String) -> Rate? {
        table.filter { model.hasPrefix($0.prefix) }.max { $0.prefix.count < $1.prefix.count }?.rate
    }

    /// Returns nil for unknown models so callers can skip rather than guess.
    public static func cost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double? {
        guard let r = rate(for: model) else { return nil }
        return (Double(input) * r.input + Double(output) * r.output
                + Double(cacheRead) * r.cacheRead + Double(cacheWrite) * r.cacheWrite) / 1_000_000
    }
}
