import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex = "Codex", claude = "Claude"
    public var id: String { rawValue }
}

public struct QuotaWindow: Codable, Sendable, Equatable {
    public var label: String
    public var usedPercent: Double
    public var resetsAt: Date?
    public init(label: String, usedPercent: Double, resetsAt: Date? = nil) {
        self.label = label; self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }
    public var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

public struct QuotaSnapshot: Codable, Sendable, Equatable {
    public var provider: Provider
    public var windows: [QuotaWindow]
    public var observedAt: Date
    public var source: String
    public init(provider: Provider, windows: [QuotaWindow], observedAt: Date, source: String) {
        self.provider = provider; self.windows = windows; self.observedAt = observedAt; self.source = source
    }
}

/// Input excludes cached reads and writes. Output already includes reasoning tokens.
public struct TokenUsage: Codable, Sendable, Equatable {
    public var input: Int64
    public var output: Int64
    public var cacheRead: Int64
    public var cacheWrite: Int64
    public init(input: Int64 = 0, output: Int64 = 0, cacheRead: Int64 = 0, cacheWrite: Int64 = 0) {
        self.input = input; self.output = output; self.cacheRead = cacheRead; self.cacheWrite = cacheWrite
    }
    public var total: Int64 {
        Self.saturatingAdd(Self.saturatingAdd(input, output), Self.saturatingAdd(cacheRead, cacheWrite))
    }
    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(input: saturatingAdd(lhs.input, rhs.input), output: saturatingAdd(lhs.output, rhs.output),
             cacheRead: saturatingAdd(lhs.cacheRead, rhs.cacheRead), cacheWrite: saturatingAdd(lhs.cacheWrite, rhs.cacheWrite))
    }

    private static func saturatingAdd(_ left: Int64, _ right: Int64) -> Int64 {
        let (value, overflow) = left.addingReportingOverflow(right)
        return overflow ? (left >= 0 && right >= 0 ? .max : .min) : value
    }
}

public struct UsageEvent: Codable, Sendable, Equatable {
    public var id: String
    public var provider: Provider
    public var model: String
    public var timestamp: Date
    public var tokens: TokenUsage
    public init(id: String, provider: Provider, model: String, timestamp: Date, tokens: TokenUsage) {
        self.id = id; self.provider = provider; self.model = model; self.timestamp = timestamp; self.tokens = tokens
    }
}

public struct ScanResult: Sendable {
    public var events: [UsageEvent]
    public var quotas: [QuotaSnapshot]
    public var warnings: [String]
    public init(events: [UsageEvent] = [], quotas: [QuotaSnapshot] = [], warnings: [String] = []) {
        self.events = events; self.quotas = quotas; self.warnings = warnings
    }
}

public enum UsageDates {
    public static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }
}
