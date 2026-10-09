import Foundation
import XCTest
@testable import UsageCore

final class LogScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("LLMUsage-LogScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testCodexCumulativeUsageUsesBaselineSuppressesDuplicatesAndTracksModelChanges() throws {
        let codex = root.appendingPathComponent("codex")
        let file = codex.appendingPathComponent("sessions/a/session.jsonl")
        try write([
            "{\"timestamp\":\"2026-10-07T23:59:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"session-a\"}}",
            "{\"timestamp\":\"2026-10-07T23:59:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-before\"}}",
            codexToken(at: "2026-10-07T23:59:30Z", input: 100, output: 10, cached: 20),
            "{truncated",
            codexToken(at: "2026-10-08T00:01:00Z", input: 150, output: 25, cached: 40),
            codexToken(at: "2026-10-08T00:01:20Z", input: 150, output: 25, cached: 40),
            "{\"timestamp\":\"2026-10-08T00:02:00Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-after\"}}",
            codexToken(at: "2026-10-08T00:02:10Z", input: 170, output: 40, cached: 40),
            "{\"timestamp\":\"2026-10-08T00:03:00Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"rate_limits\",\"rate_limits\":{\"primary\":{\"used_percent\":70,\"window_minutes\":300,\"resets_at\":\"2026-10-08T05:00:00Z\"}}}}"
        ], to: file)
        try FileManager.default.createDirectory(
            at: codex.appendingPathComponent("archived_sessions"),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: file, to: codex.appendingPathComponent("archived_sessions/copied.jsonl"))

        let result = LocalLogScanner().scan(
            codexRoot: codex,
            claudeRoot: root.appendingPathComponent("claude"),
            since: date("2026-10-08T00:00:00Z")
        )

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events.map(\.model), ["gpt-before", "gpt-after"])
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 30, output: 15, cacheRead: 20))
        XCTAssertEqual(result.events[1].tokens, TokenUsage(input: 20, output: 15))
        XCTAssertEqual(result.quotas.count, 1)
        XCTAssertEqual(result.quotas[0].windows, [QuotaWindow(label: "5시간 한도", usedPercent: 70, resetsAt: date("2026-10-08T05:00:00Z"))])
    }

    func testCodexPrefersCompleteDuplicateAndOrdersEventsDespiteMalformedTail() throws {
        let codex = root.appendingPathComponent("codex")
        try write([
            "{\"timestamp\":\"2026-10-07T23:58:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"duplicate\"}}",
            "{\"timestamp\":\"2026-10-07T23:58:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-complete\"}}",
            codexToken(at: "2026-10-07T23:59:00Z", input: 100, output: 10, cached: 20),
            codexToken(at: "2026-10-08T00:03:00Z", input: 150, output: 25, cached: 40)
        ], to: codex.appendingPathComponent("sessions/complete.jsonl"))
        try write([
            "{\"timestamp\":\"2026-10-07T23:58:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"duplicate\"}}",
            "{\"timestamp\":\"2026-10-07T23:58:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-incomplete\"}}",
            codexToken(at: "2026-10-07T23:59:00Z", input: 100, output: 10, cached: 20),
            String(repeating: "x", count: 1_100_000)
        ], to: codex.appendingPathComponent("archived_sessions/truncated-copy.jsonl"))
        try write([
            "{\"timestamp\":\"2026-10-08T00:02:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"other\"}}",
            "{\"timestamp\":\"2026-10-08T00:02:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-other\"}}",
            codexToken(at: "2026-10-08T00:02:02Z", input: 20, output: 4, cached: 0)
        ], to: codex.appendingPathComponent("sessions/other.jsonl"))

        let result = LocalLogScanner().scan(
            codexRoot: codex,
            claudeRoot: root.appendingPathComponent("claude"),
            since: date("2026-10-08T00:00:00Z")
        )

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.events.map(\.model), ["gpt-other", "gpt-complete"])
        XCTAssertEqual(result.events.map(\.timestamp), [date("2026-10-08T00:02:02Z"), date("2026-10-08T00:03:00Z")])
        XCTAssertEqual(result.events.last?.tokens, TokenUsage(input: 30, output: 15, cacheRead: 20))
    }

    func testCodexSeparatesVerifiedCacheWritesAndKeepsReasoningWithinOutput() throws {
        let codex = root.appendingPathComponent("codex")
        try write([
            "{\"timestamp\":\"2026-10-08T01:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"session-cache\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-cache\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:02Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"last_token_usage\":{\"input_tokens\":999},\"total_token_usage\":{\"input_tokens\":100,\"output_tokens\":10,\"cached_input_tokens\":40,\"cache_write_input_tokens\":10,\"reasoning_output_tokens\":6,\"total_tokens\":110}}}}"
        ], to: codex.appendingPathComponent("sessions/cache.jsonl"))

        let result = LocalLogScanner().scan(codexRoot: codex, claudeRoot: root, since: .distantPast)

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 50, output: 10, cacheRead: 40, cacheWrite: 10))
        XCTAssertEqual(result.events[0].tokens.total, 110)
    }

    func testPersistentScannerInvalidatesCachedFileAfterAppendAndTruncate() throws {
        let codex = root.appendingPathComponent("codex")
        let file = codex.appendingPathComponent("sessions/cacheable.jsonl")
        let initial = [
            "{\"timestamp\":\"2026-10-08T01:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"cacheable\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-cacheable\"}}",
            codexToken(at: "2026-10-08T01:00:02Z", input: 100, output: 10, cached: 20)
        ]
        try write(initial, to: file)
        let newlineHandle = try FileHandle(forWritingTo: file)
        try newlineHandle.seekToEnd()
        try newlineHandle.write(contentsOf: Data("\n".utf8))
        try newlineHandle.close()
        let scanner = LocalLogScanner()
        let since = date("2026-10-08T00:00:00Z")

        let first = scanner.scan(codexRoot: codex, claudeRoot: root, since: since)
        let unchanged = scanner.scan(codexRoot: codex, claudeRoot: root, since: since)
        XCTAssertEqual(unchanged.events, first.events)

        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(codexToken(at: "2026-10-08T01:01:00Z", input: 150, output: 20, cached: 30).utf8))
        try handle.close()
        let appended = scanner.scan(codexRoot: codex, claudeRoot: root, since: since)
        XCTAssertEqual(appended.events.count, 2)
        XCTAssertEqual(appended.events.last?.tokens, TokenUsage(input: 40, output: 10, cacheRead: 10))

        try write([
            "{\"timestamp\":\"2026-10-08T01:02:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"cacheable\"}}",
            "{\"timestamp\":\"2026-10-08T01:02:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-rewritten\"}}",
            codexToken(at: "2026-10-08T01:02:02Z", input: 12, output: 3, cached: 2)
        ], to: file)
        let truncated = scanner.scan(codexRoot: codex, claudeRoot: root, since: since)
        XCTAssertEqual(truncated.events.count, 1)
        XCTAssertEqual(truncated.events[0].model, "gpt-rewritten")
        XCTAssertEqual(truncated.events[0].tokens, TokenUsage(input: 10, output: 3, cacheRead: 2))
    }

    func testCodexSkipsLargeResponseItemBeforeJSONDecoding() throws {
        let codex = root.appendingPathComponent("codex")
        try write([
            "{\"timestamp\":\"2026-10-08T01:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"large-row\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-large-row\"}}",
            "{\"type\":\"response_item\",\"payload\":{\"blob\":\"" + String(repeating: "x", count: 1_100_000) + "\"}}",
            codexToken(at: "2026-10-08T01:00:02Z", input: 12, output: 3, cached: 2)
        ], to: codex.appendingPathComponent("sessions/large-row.jsonl"))

        let result = LocalLogScanner().scan(codexRoot: codex, claudeRoot: root, since: .distantPast)

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 10, output: 3, cacheRead: 2))
    }

    func testCodexDiscardsMultiMegabyteMalformedLineAndContinuesAtNextTokenRow() throws {
        let codex = root.appendingPathComponent("codex")
        try write([
            "{\"timestamp\":\"2026-10-08T01:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"discarded-tail\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-after-tail\"}}",
            "{malformed:\"" + String(repeating: "x", count: 3 * 1_024 * 1_024) + "\"}",
            codexToken(at: "2026-10-08T01:00:02Z", input: 12, output: 3, cached: 2)
        ], to: codex.appendingPathComponent("sessions/discarded-tail.jsonl"))

        let result = LocalLogScanner().scan(codexRoot: codex, claudeRoot: root, since: .distantPast)

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].model, "gpt-after-tail")
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 10, output: 3, cacheRead: 2))
    }

    func testPersistentScannerReplaysAFormerPartialFinalLine() throws {
        let codex = root.appendingPathComponent("codex")
        let file = codex.appendingPathComponent("sessions/partial.jsonl")
        try write([
            "{\"timestamp\":\"2026-10-08T01:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"partial\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-partial\"}}"
        ], to: file)
        let incomplete = codexToken(at: "2026-10-08T01:00:02Z", input: 12, output: 3, cached: 2)
        let split = incomplete.index(incomplete.startIndex, offsetBy: incomplete.count / 2)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(("\n" + incomplete[..<split]).utf8))
        try handle.close()

        let scanner = LocalLogScanner()
        XCTAssertTrue(scanner.scan(codexRoot: codex, claudeRoot: root, since: .distantPast).events.isEmpty)

        let complete = try FileHandle(forWritingTo: file)
        try complete.seekToEnd()
        try complete.write(contentsOf: Data(incomplete[split...].utf8))
        try complete.close()

        let result = scanner.scan(codexRoot: codex, claudeRoot: root, since: .distantPast)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 10, output: 3, cacheRead: 2))
    }

    func testPersistentScannerRejectsInPlaceLargerRewrite() throws {
        let codex = root.appendingPathComponent("codex")
        let file = codex.appendingPathComponent("sessions/rewrite.jsonl")
        try write([
            "{\"timestamp\":\"2026-10-08T01:00:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"rewrite\"}}",
            "{\"timestamp\":\"2026-10-08T01:00:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-old\"}}",
            codexToken(at: "2026-10-08T01:00:02Z", input: 100, output: 10, cached: 20)
        ], to: file)
        let scanner = LocalLogScanner()
        XCTAssertEqual(scanner.scan(codexRoot: codex, claudeRoot: root, since: .distantPast).events.count, 1)

        try write([
            "{\"timestamp\":\"2026-10-08T01:01:00Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"rewritten-with-a-longer-identifier\"}}",
            "{\"timestamp\":\"2026-10-08T01:01:01Z\",\"type\":\"turn_context\",\"payload\":{\"model\":\"gpt-new\"}}",
            codexToken(at: "2026-10-08T01:01:02Z", input: 12, output: 3, cached: 2),
            "{\"type\":\"note\",\"payload\":\"make this replacement larger than the cached file\"}"
        ], to: file)
        let result = scanner.scan(codexRoot: codex, claudeRoot: root, since: .distantPast)
        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].model, "gpt-new")
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 10, output: 3, cacheRead: 2))
    }

    func testClaudeChoosesHighestStreamingUsageAndFindsSubagentsRecursively() throws {
        let claude = root.appendingPathComponent("claude")
        try write([
            "not json",
            claudeAssistant(id: "message-1", requestID: "request-1", at: "2026-10-08T02:00:00Z", model: "claude-a", input: 10, output: 5, cacheRead: 3, cacheWrite: 2),
            claudeAssistant(id: "message-1", requestID: "request-1", at: "2026-10-08T02:00:02Z", model: "claude-a", input: 10, output: 8, cacheRead: 3, cacheWrite: 2)
        ], to: claude.appendingPathComponent("projects/project/main.jsonl"))
        try write([
            claudeAssistant(id: "message-2", requestID: "request-2", at: "2026-10-08T02:01:00Z", model: "claude-subagent", input: 4, output: 6, cacheRead: 1, cacheWrite: 0)
        ], to: claude.appendingPathComponent("projects/project/subagents/worker.jsonl"))

        let result = LocalLogScanner().scan(
            codexRoot: root.appendingPathComponent("codex"),
            claudeRoot: claude,
            since: date("2026-10-08T02:00:01Z")
        )

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.events.count, 2)
        XCTAssertEqual(result.events[0].model, "claude-a")
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 10, output: 8, cacheRead: 3, cacheWrite: 2))
        XCTAssertEqual(result.events[1].model, "claude-subagent")
        XCTAssertEqual(result.events[1].tokens, TokenUsage(input: 4, output: 6, cacheRead: 1))
    }

    func testClaudeCacheExcludesRecordsBeforeRequestedWindowBeforeDeduplication() throws {
        let claude = root.appendingPathComponent("claude")
        try write([
            claudeAssistant(id: "streamed", requestID: "request", at: "2026-10-08T01:59:59Z", model: "claude-old", input: 10, output: 100, cacheRead: 0, cacheWrite: 0),
            claudeAssistant(id: "streamed", requestID: "request", at: "2026-10-08T02:00:01Z", model: "claude-new", input: 10, output: 8, cacheRead: 0, cacheWrite: 0)
        ], to: claude.appendingPathComponent("projects/project/stream.jsonl"))

        let result = LocalLogScanner().scan(
            codexRoot: root.appendingPathComponent("codex"),
            claudeRoot: claude,
            since: date("2026-10-08T02:00:00Z")
        )

        XCTAssertEqual(result.events.count, 1)
        XCTAssertEqual(result.events[0].model, "claude-new")
        XCTAssertEqual(result.events[0].tokens, TokenUsage(input: 10, output: 8))
    }

    private func codexToken(at timestamp: String, input: Int, output: Int, cached: Int) -> String {
        "{\"timestamp\":\"\(timestamp)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cached_input_tokens\":\(cached),\"total_tokens\":\(input + output)}}}}"
    }

    private func claudeAssistant(id: String, requestID: String, at timestamp: String, model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"\(timestamp)\",\"requestId\":\"\(requestID)\",\"message\":{\"id\":\"\(id)\",\"model\":\"\(model)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),\"cache_read_input_tokens\":\(cacheRead),\"cache_creation_input_tokens\":\(cacheWrite)}}}"
    }

    private func write(_ lines: [String], to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try lines.joined(separator: "\n").data(using: .utf8)!.write(to: file)
    }

    private func date(_ string: String) -> Date {
        try! XCTUnwrap(UsageDates.parse(string))
    }
}
