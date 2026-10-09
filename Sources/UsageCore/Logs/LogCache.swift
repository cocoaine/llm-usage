import Foundation

/// Process-local cache. It contains only parsed timestamps, models, quota values,
/// and token counts; JSONL text is never persisted or retained.
final class LogCache: @unchecked Sendable {
    struct Key: Equatable {
        var modifiedAt: Date?
        var size: Int64?
        var since: Date
        var identity: FileIdentity?
        var prefixFingerprint: UInt64?
        var tailFingerprint: UInt64?
    }

    private struct CodexEntry { var key: Key; var result: CodexParseResult; var lastAccess: UInt64 }
    private struct ClaudeEntry { var key: Key; var result: ClaudeFileResult; var lastAccess: UInt64 }
    private let lock = NSLock()
    private var codexEntries: [String: CodexEntry] = [:]
    private var claudeEntries: [String: ClaudeEntry] = [:]
    private var accessCounter: UInt64 = 0

    func codex(path: String, key: Key) -> CodexParseResult? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = codexEntries[path], entry.key == key else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        codexEntries[path] = entry
        return entry.result
    }

    func storeCodex(_ result: CodexParseResult, path: String, key: Key) {
        lock.lock(); defer { lock.unlock() }
        accessCounter &+= 1
        codexEntries[path] = CodexEntry(key: key, result: result, lastAccess: accessCounter)
        trimCodex()
    }

    func appendableCodex(path: String, key: Key) -> (result: CodexParseResult, offset: UInt64, tailFingerprint: UInt64?)? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = codexEntries[path], entry.key.since == key.since,
              let previousSize = entry.key.size, let currentSize = key.size,
              currentSize > previousSize,
              entry.key.identity == key.identity,
              entry.key.prefixFingerprint == key.prefixFingerprint,
              (entry.key.modifiedAt ?? .distantPast) <= (key.modifiedAt ?? .distantPast) else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        codexEntries[path] = entry
        return (entry.result, UInt64(previousSize), entry.key.tailFingerprint)
    }

    func claude(path: String, key: Key) -> ClaudeFileResult? {
        lock.lock(); defer { lock.unlock() }
        guard var entry = claudeEntries[path], entry.key == key else { return nil }
        accessCounter &+= 1
        entry.lastAccess = accessCounter
        claudeEntries[path] = entry
        return entry.result
    }

    func storeClaude(_ result: ClaudeFileResult, path: String, key: Key) {
        lock.lock(); defer { lock.unlock() }
        accessCounter &+= 1
        claudeEntries[path] = ClaudeEntry(key: key, result: result, lastAccess: accessCounter)
        trimClaude()
    }

    private func trimCodex() {
        let stale = codexEntries.sorted { $0.value.lastAccess < $1.value.lastAccess }.prefix(max(0, codexEntries.count - 128)).map(\.key)
        for path in stale { codexEntries.removeValue(forKey: path) }
    }

    private func trimClaude() {
        let stale = claudeEntries.sorted { $0.value.lastAccess < $1.value.lastAccess }.prefix(max(0, claudeEntries.count - 128)).map(\.key)
        for path in stale { claudeEntries.removeValue(forKey: path) }
    }
}
