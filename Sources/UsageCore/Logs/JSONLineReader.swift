import Foundation
import CoreFoundation

typealias JSONObject = [String: Any]

enum JSONLineReader {
    static let maximumLineBytes = 1_048_576
    private static let headerLimit = 8_192

    static func read(
        file: URL,
        offset: UInt64 = 0,
        through endOffset: UInt64? = nil,
        providerName: String,
        skipCodexResponseItems: Bool,
        warnings: inout [String],
        consume: (JSONObject) -> Void
    ) {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            if offset > 0 { try handle.seek(toOffset: offset) }
            var bytesRemaining = endOffset.map { $0 > offset ? $0 - offset : 0 }
            var remainder = Data()
            var discardingLine = false
            while bytesRemaining.map({ $0 > 0 }) ?? true {
                // The discarded path retains no line data, so a larger read
                // avoids tens of thousands of syscalls for image payload rows.
                let preferredCount = discardingLine ? 1_024 * 1_024 : 64 * 1_024
                let count = min(preferredCount, Int(bytesRemaining ?? UInt64(preferredCount)))
                guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else { break }
                if let remaining = bytesRemaining { bytesRemaining = remaining - UInt64(chunk.count) }
                // Once a line has crossed the limit, `remainder` deliberately
                // contains none of it. Do not append later chunks until its
                // newline arrives, otherwise a corrupt line can grow without
                // bound one 64 KiB read at a time.
                var next = chunk
                if discardingLine {
                    guard let newline = next.firstIndex(of: 0x0A) else { continue }
                    next = Data(next[next.index(after: newline)...])
                    discardingLine = false
                }
                remainder.append(next)
                while let newline = remainder.firstIndex(of: 0x0A) {
                    let line = remainder.prefix(upTo: newline)
                    remainder.removeSubrange(...newline)
                    if !discardingLine, line.count <= maximumLineBytes,
                       !(skipCodexResponseItems && topLevelType(in: line) == "response_item") {
                        consumeJSON(line, consume: consume)
                    }
                    discardingLine = false
                }
                // Codex response_item rows can contain multi-megabyte binary or image
                // payloads. Their top-level type appears in the header, so discard the
                // rest of that line before it reaches JSONSerialization or memory.
                if !discardingLine, skipCodexResponseItems, remainder.count >= headerLimit,
                   topLevelType(in: remainder) == "response_item" {
                    remainder.removeAll(keepingCapacity: false)
                    discardingLine = true
                } else if !discardingLine, remainder.count > maximumLineBytes {
                    remainder.removeAll(keepingCapacity: false)
                    discardingLine = true
                }
            }
            if !discardingLine, !remainder.isEmpty, remainder.count <= maximumLineBytes,
               !(skipCodexResponseItems && topLevelType(in: remainder) == "response_item") {
                consumeJSON(remainder, consume: consume)
            }
        } catch {
            warnings.append("Unable to read a \(providerName) usage log.")
        }
    }

    static func dictionary(_ value: Any?) -> JSONObject? { value as? JSONObject }
    static func string(_ value: Any?) -> String? { value as? String }

    static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        // `Double(Int64.max)` rounds up to 2^63, which traps when converted
        // back to Int64. Parsed usage values are intentionally much smaller.
        guard value.isFinite, value >= 0, value <= 1_000_000_000_000_000, value.rounded() == value else { return nil }
        return Int64(value)
    }

    static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue
    }

    static func date(_ value: Any?) -> Date? {
        if let string = value as? String { return UsageDates.parse(string) }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            let seconds = number.doubleValue > 10_000_000_000 ? number.doubleValue / 1_000 : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private static func consumeJSON(_ data: Data, consume: (JSONObject) -> Void) {
        guard let value = try? JSONSerialization.jsonObject(with: data), let object = value as? JSONObject else { return }
        consume(object)
    }

    private static func topLevelType(in data: Data) -> String? {
        let limit = min(data.count, headerLimit)
        var index = 0
        skipWhitespace(in: data, index: &index, limit: limit)
        guard index < limit, data[index] == 0x7B else { return nil }
        index += 1
        while index < limit {
            skipWhitespace(in: data, index: &index, limit: limit)
            guard index < limit, data[index] != 0x7D,
                  let key = readJSONString(in: data, index: &index, limit: limit) else { return nil }
            skipWhitespace(in: data, index: &index, limit: limit)
            guard index < limit, data[index] == 0x3A else { return nil }
            index += 1
            skipWhitespace(in: data, index: &index, limit: limit)
            if key == "type" { return readJSONString(in: data, index: &index, limit: limit) }
            guard skipJSONValue(in: data, index: &index, limit: limit) else { return nil }
            skipWhitespace(in: data, index: &index, limit: limit)
            guard index < limit else { return nil }
            if data[index] == 0x2C { index += 1 }
            else if data[index] == 0x7D { return nil }
            else { return nil }
        }
        return nil
    }

    private static func skipWhitespace(in data: Data, index: inout Int, limit: Int) {
        while index < limit, [0x09, 0x0A, 0x0D, 0x20].contains(data[index]) { index += 1 }
    }

    private static func readJSONString(in data: Data, index: inout Int, limit: Int) -> String? {
        guard index < limit, data[index] == 0x22 else { return nil }
        index += 1
        let start = index
        var escaped = false
        while index < limit {
            let byte = data[index]
            if !escaped, byte == 0x22 {
                let string = String(data: data.subdata(in: start ..< index), encoding: .utf8)
                index += 1
                return string
            }
            if byte == 0x5C, !escaped { escaped = true } else { escaped = false }
            index += 1
        }
        return nil
    }

    private static func skipJSONValue(in data: Data, index: inout Int, limit: Int) -> Bool {
        guard index < limit else { return false }
        if data[index] == 0x22 { return skipJSONString(in: data, index: &index, limit: limit) }
        if data[index] != 0x7B, data[index] != 0x5B {
            while index < limit, data[index] != 0x2C, data[index] != 0x7D { index += 1 }
            return index < limit
        }
        var depth = 0, inString = false, escaped = false
        while index < limit {
            let byte = data[index]
            if inString {
                if byte == 0x5C, !escaped { escaped = true }
                else if byte == 0x22, !escaped { inString = false }
                else { escaped = false }
            } else if byte == 0x22 { inString = true }
            else if byte == 0x7B || byte == 0x5B { depth += 1 }
            else if byte == 0x7D || byte == 0x5D {
                depth -= 1
                if depth == 0 { index += 1; return true }
            }
            index += 1
        }
        return false
    }

    private static func skipJSONString(in data: Data, index: inout Int, limit: Int) -> Bool {
        guard index < limit, data[index] == 0x22 else { return false }
        index += 1
        var escaped = false
        while index < limit {
            let byte = data[index]
            if byte == 0x22, !escaped { index += 1; return true }
            if byte == 0x5C, !escaped { escaped = true } else { escaped = false }
            index += 1
        }
        return false
    }
}
