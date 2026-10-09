import Foundation

enum CodexLogParser {
    static func parse(
        file: LogFile,
        since: Date,
        startingAt offset: UInt64 = 0,
        prior: CodexParseResult? = nil,
        warnings: inout [String]
    ) -> CodexParseResult {
        var state = prior?.state ?? .initial
        var events = prior?.events ?? []
        JSONLineReader.read(
            file: file.url,
            offset: offset,
            through: file.size.flatMap { $0 >= 0 ? UInt64($0) : nil },
            providerName: "Codex",
            skipCodexResponseItems: true,
            warnings: &warnings
        ) { object in
            consume(object, state: &state, events: &events, since: since)
        }
        let sessionID = state.sessionID
        let stableID = sessionID ?? "file-\(file.url.lastPathComponent)"
        // Keep IDs stable while the parser state only tracks numeric records.
        for index in events.indices where events[index].id.hasPrefix("codex:pending:") {
            let suffix = events[index].id.dropFirst("codex:pending:".count)
            events[index].id = "codex:\(stableID):\(suffix)"
        }
        return CodexParseResult(
            sessionID: sessionID,
            events: events,
            latestQuota: state.latestQuota,
            tokenRecordCount: state.tokenRecordCount,
            latestTokenTimestamp: state.latestTokenTimestamp,
            modifiedAt: file.modifiedAt,
            filePath: file.path,
            state: state
        )
    }

    private static func consume(
        _ object: JSONObject,
        state: inout CodexParserState,
        events: inout [UsageEvent],
        since: Date
    ) {
        let payload = JSONLineReader.dictionary(object["payload"])
        let type = JSONLineReader.string(object["type"]) ?? JSONLineReader.string(payload?["type"])
        let timestamp = JSONLineReader.date(object["timestamp"]) ?? JSONLineReader.date(payload?["timestamp"])

        if type == "session_meta", let id = JSONLineReader.string(payload?["id"]) ?? JSONLineReader.string(object["id"]) {
            state.sessionID = id
        }
        if type == "turn_context", let model = JSONLineReader.string(payload?["model"]) ?? JSONLineReader.string(object["model"]) {
            state.model = model
        }
        if let quota = quotaSnapshot(in: object, observedAt: timestamp ?? .distantPast),
           state.latestQuota == nil || quota.observedAt >= state.latestQuota!.observedAt {
            state.latestQuota = quota
        }

        guard type == "event_msg", JSONLineReader.string(payload?["type"]) == "token_count",
              let info = JSONLineReader.dictionary(payload?["info"]),
              let totalUsage = JSONLineReader.dictionary(info["total_token_usage"]),
              let current = cumulativeTokens(from: totalUsage) else { return }
        let delta = current.delta(since: state.previous)
        state.previous = current
        state.tokenRecordCount += 1
        if let timestamp, state.latestTokenTimestamp == nil || timestamp > state.latestTokenTimestamp! {
            state.latestTokenTimestamp = timestamp
        }
        guard let delta, let timestamp, timestamp >= since else { return }
        state.eventIndex += 1
        events.append(UsageEvent(
            id: "codex:pending:\(state.eventIndex)", provider: .codex,
            model: state.model, timestamp: timestamp, tokens: delta
        ))
    }

    private static func cumulativeTokens(from object: JSONObject) -> CumulativeTokens? {
        let reportedTotal: Int64?
        if let totalValue = object["total_tokens"] {
            guard let total = tokenCount(totalValue) else { return nil }
            reportedTotal = total
        } else {
            reportedTotal = nil
        }
        guard let rawInput = tokenCount(object["input_tokens"]),
              let output = tokenCount(object["output_tokens"]),
              let cacheRead = tokenCount(in: object, keys: ["cached_input_tokens", "cache_read_input_tokens"]),
              let reportedCacheWrite = tokenCount(in: object, keys: ["cache_write_input_tokens", "cache_creation_input_tokens"]) else { return nil }
        let cacheWrite = reportedCacheWrite > 0 && reportedTotal == rawInput + output ? reportedCacheWrite : 0
        return CumulativeTokens(usage: TokenUsage(
            input: max(0, rawInput - cacheRead - cacheWrite), output: output,
            cacheRead: cacheRead, cacheWrite: cacheWrite
        ))
    }

    private static func quotaSnapshot(in object: JSONObject, observedAt: Date) -> QuotaSnapshot? {
        guard let limits = JSONLineReader.dictionary(JSONLineReader.dictionary(object["payload"])?["rate_limits"])
            ?? JSONLineReader.dictionary(object["rate_limits"]) else { return nil }
        let windows = ["primary", "secondary"].compactMap { name -> QuotaWindow? in
            guard let window = JSONLineReader.dictionary(limits[name]),
                  let used = JSONLineReader.double(window["used_percent"]), used.isFinite, (0...100).contains(used),
                  let minutes = JSONLineReader.integer(window["window_minutes"]), minutes > 0 else { return nil }
            let label = minutes % 1_440 == 0 ? "\(minutes / 1_440)일 한도" : minutes % 60 == 0 ? "\(minutes / 60)시간 한도" : "\(minutes)분 한도"
            return QuotaWindow(label: label, usedPercent: used, resetsAt: JSONLineReader.date(window["resets_at"]))
        }
        return windows.isEmpty ? nil : QuotaSnapshot(provider: .codex, windows: windows, observedAt: observedAt, source: "Codex CLI 기록")
    }

    private static func tokenCount(_ value: Any?) -> Int64? {
        guard let value = JSONLineReader.integer(value), value <= 1_000_000_000_000_000 else { return nil }
        return value
    }

    private static func tokenCount(in object: JSONObject, keys: [String]) -> Int64? {
        for key in keys where object[key] != nil { return tokenCount(object[key]) }
        return 0
    }
}
