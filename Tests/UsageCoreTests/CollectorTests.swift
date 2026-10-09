import Foundation
import XCTest
@testable import UsageCore

final class CollectorTests: XCTestCase {
    func testCodexBucketSelectionAndWindowOrdering() throws {
        let snapshot = try CodexQuotaClient.parse(result: [
            "rateLimits": ["primary": ["usedPercent": 99]],
            "rateLimitsByLimitId": ["codex": [
                "primary": ["usedPercent": 23, "windowDurationMins": 300, "resetsAt": 2_000_000_000],
                "secondary": ["usedPercent": 67, "windowDurationMins": 10080]
            ]]
        ])
        XCTAssertEqual(snapshot.windows.map(\.label), ["5시간 한도", "7일 한도"])
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [77, 33])
    }

    func testAbsentQuotaDoesNotBecomeFullAllowance() throws {
        let snapshot = try CodexQuotaClient.parse(result: ["rateLimits": ["primary": NSNull()]])
        XCTAssertTrue(snapshot.windows.isEmpty)
        let bridge = try ClaudeBridge.parse(Data("{\"rate_limits\":null}".utf8))
        XCTAssertTrue(bridge.windows.isEmpty)
    }

    func testClaudePersistsOnlyNumericSnapshotAndPreservesOnAbsentFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("snapshot.json")
        let input = Data("""
        {"secret":"must-never-persist","transcript_path":"private-conversation","rate_limits":{"five_hour":{"used_percentage":25,"resets_at":2000000000},"seven_day":{"used_percentage":40}}}
        """.utf8)
        let snapshot = try ClaudeBridge.capture(input, at: url)
        XCTAssertEqual(snapshot.windows.map(\.remainingPercent), [75, 60])
        let stored = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(stored.contains("must-never-persist"))
        XCTAssertFalse(stored.contains("private-conversation"))
        _ = try ClaudeBridge.capture(Data("{}".utf8), at: url)
        XCTAssertEqual(ClaudeBridge.read(at: url), snapshot)
    }

    func testClaudeInstallerPreservesSettingsAndBacksUp() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settings = root.appendingPathComponent("settings.json")
        try Data("{\"theme\":\"dark\",\"hooks\":{\"Stop\":[]}}".utf8).write(to: settings)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settings.path)
        let executable = URL(fileURLWithPath: "/Applications/LLM Usage.app/Contents/MacOS/LLMUsage")
        try ClaudeBridge.install(executable: executable, configDirectory: root)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        XCTAssertEqual(object["theme"] as? String, "dark")
        XCTAssertNotNil(object["hooks"])
        XCTAssertEqual((object["statusLine"] as? [String: Any])?["command"] as? String,
                       "'/Applications/LLM Usage.app/Contents/MacOS/LLMUsage' --capture-claude")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count, 2)
        XCTAssertEqual(try permissions(of: settings), 0o600)
        let backup = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("settings.llmusage-backup-") })
        XCTAssertEqual(try permissions(of: backup), 0o600)
        try ClaudeBridge.install(executable: executable, configDirectory: root)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count, 2)
    }

    func testClaudeInstallerRefusesToOverwriteExistingStatusline() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("settings.json")
        let original = Data("{\"statusLine\":{\"type\":\"command\",\"command\":\"my-status\"}}".utf8)
        try original.write(to: url)
        XCTAssertThrowsError(try ClaudeBridge.install(executable: URL(fileURLWithPath: "/app"), configDirectory: root))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    func testCodexProcessHandshakeAndResponse() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("fake-codex")
        let script = """
        #!/bin/sh
        read -r init
        printf '%s\\n' '{"id":1,"result":{}}'
        read -r initialized
        read -r request
        printf '%s\\n' '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let snapshot = try CodexQuotaClient(executable: executable, timeout: 2).fetch()
        XCTAssertEqual(snapshot.windows.first?.remainingPercent, 80)
    }

    func testCodexProcessTimeoutIsBounded() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let executable = root.appendingPathComponent("unresponsive-codex")
        try Data("#!/bin/sh\nexec /bin/sleep 5\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let start = Date()
        XCTAssertThrowsError(try CodexQuotaClient(executable: executable, timeout: 0.3).fetch())
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }

    func testTokenUsageSaturatesMalformedAggregateTotals() {
        let usage = TokenUsage(input: .max, output: 1, cacheRead: .max, cacheWrite: 1)
        XCTAssertEqual(usage.total, .max)
        XCTAssertEqual(TokenUsage(input: .max) + TokenUsage(input: 1), TokenUsage(input: .max))
    }

    private func permissions(of url: URL) throws -> Int {
        let value = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        return try XCTUnwrap(value).intValue & 0o777
    }
}
