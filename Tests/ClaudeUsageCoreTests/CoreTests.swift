import XCTest
@testable import ClaudeUsageCore

final class CoreTests: XCTestCase {
    func testStatuslineParsing() {
        var s = UsageSnapshot()
        let json = #"{"rate_limits":{"five_hour":{"used_percentage":12.5,"resets_at":1790000000},"seven_day":{"used_percentage":40}},"context_window":{"used_percentage":6,"context_window_size":1000000}}"#
        StatuslineIngest.apply(Data(json.utf8), to: &s)
        XCTAssertEqual(s.limits.count, 2)
        XCTAssertEqual(s.limits[0].percentUsed, 12.5)
        XCTAssertEqual(s.context?.percentUsed, 6)
    }
    /// Real payload captured from Claude Code 2.1.296 (ids, paths and session data removed).
    func testRealStatuslinePayload() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "statusline-2.1.296", withExtension: "json", subdirectory: "Fixtures"))
        var s = UsageSnapshot()
        StatuslineIngest.apply(try Data(contentsOf: url), to: &s)
        XCTAssertEqual(s.limits.map(\.label), ["5-hour limit", "Weekly · all models"])
        XCTAssertEqual(s.limits[0].percentUsed, 6)
        XCTAssertEqual(s.limits[0].resetsAt, Date(timeIntervalSince1970: 1791761400))
        XCTAssertEqual(s.limits[1].percentUsed, 3)
        XCTAssertEqual(s.context?.percentUsed, 4)
        XCTAssertEqual(s.context?.tokensUsed, 36272)
        XCTAssertEqual(s.context?.windowSize, 1_000_000)
    }
    func testScanDedupes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = #"{"timestamp":"\#(ts)","requestId":"r1","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":2,"output_tokens":3,"cache_read_input_tokens":10,"cache_creation_input_tokens":5}}}"#
        try (line + "\n" + line + "\n").write(to: dir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        let days = LogScanner.scan(root: dir)
        XCTAssertEqual(days.last?.total, 20)
        // sonnet-5-5: 2*$2 + 3*$10 + 10*$0.20 + 5*$2.50 per million tokens
        XCTAssertEqual(try XCTUnwrap(days.last?.costUSD), (4 + 30 + 2 + 12.5) / 1_000_000, accuracy: 1e-12)
    }
    func testPricingPrefixAndUnknown() {
        XCTAssertEqual(Pricing.rate(for: "claude-opus-5-5")?.input, 4)
        XCTAssertEqual(Pricing.rate(for: "claude-opus-5")?.input, 5)
        XCTAssertNil(Pricing.rate(for: "<synthetic>"))
    }
}
