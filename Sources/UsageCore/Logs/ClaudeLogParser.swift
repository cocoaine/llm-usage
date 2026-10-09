import Foundation

enum ClaudeLogParser {
    static func parse(file: LogFile, since: Date, warnings: inout [String]) -> ClaudeFileResult {
        var records: [String: ClaudeRecord] = [:]
        var anonymousRecord = 0
        JSONLineReader.read(
            file: file.url,
            through: file.size.flatMap { $0 >= 0 ? UInt64($0) : nil },
            providerName: "Claude",
            skipCodexResponseItems: false,
            warnings: &warnings
        ) { object in
            guard JSONLineReader.string(object["type"]) == "assistant",
                  let message = JSONLineReader.dictionary(object["message"]),
                  let usage = JSONLineReader.dictionary(message["usage"]),
                  let timestamp = JSONLineReader.date(object["timestamp"]),
                  timestamp >= since,
                  let tokens = tokens(from: usage) else { return }
            let messageID = JSONLineReader.string(message["id"]) ?? JSONLineReader.string(object["id"])
            let requestID = JSONLineReader.string(object["requestId"]) ?? JSONLineReader.string(object["request_id"])
            let id: String
            if let messageID, let requestID { id = "claude:\(messageID):\(requestID)" }
            else if let messageID { id = "claude:\(messageID)" }
            else if let requestID { id = "claude:request:\(requestID)" }
            else { anonymousRecord += 1; id = "claude:anonymous:\(file.path):\(anonymousRecord)" }
            let candidate = ClaudeRecord(
                id: id, timestamp: timestamp,
                model: JSONLineReader.string(message["model"]) ?? JSONLineReader.string(object["model"]) ?? "unknown",
                tokens: tokens
            )
            merge(candidate, into: &records)
        }
        return ClaudeFileResult(records: records)
    }

    static func merge(_ candidate: ClaudeRecord, into records: inout [String: ClaudeRecord]) {
        if let existing = records[candidate.id] {
            if candidate.score > existing.score || (candidate.score == existing.score && candidate.timestamp > existing.timestamp) {
                records[candidate.id] = candidate
            }
        } else {
            records[candidate.id] = candidate
        }
    }

    private static func tokens(from object: JSONObject) -> TokenUsage? {
        guard let input = tokenCount(object["input_tokens"]), let output = tokenCount(object["output_tokens"]),
              let cacheRead = tokenCount(in: object, keys: ["cache_read_input_tokens"]),
              let cacheWrite = tokenCount(in: object, keys: ["cache_creation_input_tokens"]) else { return nil }
        return TokenUsage(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite)
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
