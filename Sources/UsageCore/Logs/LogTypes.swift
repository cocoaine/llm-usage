import Foundation

struct LogFile {
    var url: URL
    var modifiedAt: Date?
    var size: Int64?
    var identity: FileIdentity?
    var prefixFingerprint: UInt64?
    var tailFingerprint: UInt64?
    var path: String { url.path }
}

/// A file-system identity and compact hashes let the incremental cache reject
/// rotations and in-place rewrites without retaining any log text.
struct FileIdentity: Equatable {
    var device: UInt64
    var inode: UInt64
}

struct CodexParseResult {
    var sessionID: String?
    var events: [UsageEvent]
    var latestQuota: QuotaSnapshot?
    var tokenRecordCount: Int
    var latestTokenTimestamp: Date?
    var modifiedAt: Date?
    var filePath: String
    var state: CodexParserState

    func isPreferred(over other: CodexParseResult) -> Bool {
        let thisLatest = latestTokenTimestamp ?? .distantPast
        let otherLatest = other.latestTokenTimestamp ?? .distantPast
        if thisLatest != otherLatest { return thisLatest > otherLatest }
        if tokenRecordCount != other.tokenRecordCount { return tokenRecordCount > other.tokenRecordCount }
        let thisModified = modifiedAt ?? .distantPast
        let otherModified = other.modifiedAt ?? .distantPast
        if thisModified != otherModified { return thisModified > otherModified }
        return filePath < other.filePath
    }
}

struct CumulativeTokens: Equatable {
    var usage: TokenUsage
    var total: Int64 { usage.total }

    func delta(since previous: CumulativeTokens?) -> TokenUsage? {
        guard let previous else { return usage.total > 0 ? usage : nil }
        guard total != previous.total else { return nil }
        if total < previous.total { return usage.total > 0 ? usage : nil }
        let value = TokenUsage(
            input: max(0, usage.input - previous.usage.input),
            output: max(0, usage.output - previous.usage.output),
            cacheRead: max(0, usage.cacheRead - previous.usage.cacheRead),
            cacheWrite: max(0, usage.cacheWrite - previous.usage.cacheWrite)
        )
        return value.total > 0 ? value : nil
    }
}

struct CodexParserState {
    var sessionID: String?
    var model: String
    var previous: CumulativeTokens?
    var eventIndex: Int
    var tokenRecordCount: Int
    var latestTokenTimestamp: Date?
    var latestQuota: QuotaSnapshot?

    static let initial = CodexParserState(
        sessionID: nil, model: "unknown", previous: nil, eventIndex: 0,
        tokenRecordCount: 0, latestTokenTimestamp: nil, latestQuota: nil
    )
}

struct ClaudeRecord {
    var id: String
    var timestamp: Date
    var model: String
    var tokens: TokenUsage
    var score: Int64 { tokens.total }
}

struct ClaudeFileResult {
    var records: [String: ClaudeRecord]
}
