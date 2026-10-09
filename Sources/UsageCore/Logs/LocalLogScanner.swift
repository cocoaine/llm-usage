import Foundation

/// Synchronous, local-only scanner for Codex and Claude Code JSONL accounting logs.
public struct LocalLogScanner: Sendable {
    private let cache: LogCache

    public init() { cache = LogCache() }

    public func scan(codexRoot: URL, claudeRoot: URL, since: Date) -> ScanResult {
        var warnings: [String] = []
        var events: [UsageEvent] = []
        var codexSessions: [String: CodexParseResult] = [:]
        var anonymousCodexFiles: [CodexParseResult] = []
        var latestCodexQuota: QuotaSnapshot?

        let codexFiles = logFiles(in: codexRoot.appendingPathComponent("sessions"), providerName: "Codex", modifiedSince: since, warnings: &warnings)
            + logFiles(in: codexRoot.appendingPathComponent("archived_sessions"), providerName: "Codex", modifiedSince: since, warnings: &warnings)
        for file in codexFiles {
            let parsed = cachedCodexFile(file, since: since, warnings: &warnings)
            if let quota = parsed.latestQuota,
               latestCodexQuota == nil || quota.observedAt >= latestCodexQuota!.observedAt {
                latestCodexQuota = quota
            }
            if let id = parsed.sessionID {
                if let existing = codexSessions[id] {
                    if parsed.isPreferred(over: existing) { codexSessions[id] = parsed }
                } else {
                    codexSessions[id] = parsed
                }
            } else {
                anonymousCodexFiles.append(parsed)
            }
        }
        for parsed in (Array(codexSessions.values) + anonymousCodexFiles).sorted(by: { $0.filePath < $1.filePath }) {
            events.append(contentsOf: parsed.events)
        }

        var claudeRecords: [String: ClaudeRecord] = [:]
        for file in logFiles(in: claudeRoot.appendingPathComponent("projects"), providerName: "Claude", modifiedSince: since, warnings: &warnings) {
            for record in cachedClaudeFile(file, since: since, warnings: &warnings).records.values {
                ClaudeLogParser.merge(record, into: &claudeRecords)
            }
        }
        events.append(contentsOf: claudeRecords.values.compactMap { record in
            guard record.timestamp >= since else { return nil }
            return UsageEvent(id: record.id, provider: .claude, model: record.model, timestamp: record.timestamp, tokens: record.tokens)
        })
        events.sort { $0.timestamp == $1.timestamp ? $0.id < $1.id : $0.timestamp < $1.timestamp }
        return ScanResult(events: events, quotas: latestCodexQuota.map { [$0] } ?? [], warnings: warnings)
    }
}

private extension LocalLogScanner {
    func logFiles(in root: URL, providerName: String, modifiedSince: Date, warnings: inout [String]) -> [LogFile] {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return [] }
        guard isDirectory.boolValue else {
            guard root.pathExtension.lowercased() == "jsonl" else { return [] }
            return [makeLogFile(root)]
        }
        var directoryReadFailed = false
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles], errorHandler: { _, _ in directoryReadFailed = true; return true }
        ) else {
            warnings.append("Unable to read a \(providerName) usage-log directory.")
            return []
        }
        var files: [LogFile] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "jsonl" {
            let file = makeLogFile(url)
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) != false else { continue }
            if let modifiedAt = file.modifiedAt, modifiedAt < modifiedSince { continue }
            files.append(file)
        }
        if directoryReadFailed { warnings.append("Unable to read a \(providerName) usage-log directory.") }
        return files.sorted { $0.path < $1.path }
    }

    func makeLogFile(_ url: URL) -> LogFile {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let size = values?.fileSize.map { Int64($0) }
        return LogFile(
            url: url,
            modifiedAt: values?.contentModificationDate,
            size: size,
            identity: fileIdentity(at: url),
            prefixFingerprint: fingerprint(of: url, endingAt: min(size ?? 0, 4_096)),
            tailFingerprint: size.flatMap { $0 >= 0 ? fingerprint(of: url, endingAt: $0) : nil }
        )
    }

    func cachedCodexFile(_ file: LogFile, since: Date, warnings: inout [String]) -> CodexParseResult {
        let key = LogCache.Key(
            modifiedAt: file.modifiedAt,
            size: file.size,
            since: since,
            identity: file.identity,
            prefixFingerprint: file.prefixFingerprint,
            tailFingerprint: file.tailFingerprint
        )
        if let result = cache.codex(path: file.path, key: key) { return result }
        if let prior = cache.appendableCodex(path: file.path, key: key),
           fileEndedWithNewline(file.url, at: prior.offset),
           cacheBoundaryMatches(file, offset: prior.offset, fingerprint: prior.tailFingerprint) {
            let result = CodexLogParser.parse(file: file, since: since, startingAt: prior.offset, prior: prior.result, warnings: &warnings)
            cache.storeCodex(result, path: file.path, key: key)
            return result
        }
        let result = CodexLogParser.parse(file: file, since: since, warnings: &warnings)
        cache.storeCodex(result, path: file.path, key: key)
        return result
    }

    func cachedClaudeFile(_ file: LogFile, since: Date, warnings: inout [String]) -> ClaudeFileResult {
        let key = LogCache.Key(
            modifiedAt: file.modifiedAt,
            size: file.size,
            since: since,
            identity: file.identity,
            prefixFingerprint: file.prefixFingerprint,
            tailFingerprint: file.tailFingerprint
        )
        if let result = cache.claude(path: file.path, key: key) { return result }
        let result = ClaudeLogParser.parse(file: file, since: since, warnings: &warnings)
        cache.storeClaude(result, path: file.path, key: key)
        return result
    }

    func fileEndedWithNewline(_ file: URL, at offset: UInt64) -> Bool {
        guard offset > 0, let handle = try? FileHandle(forReadingFrom: file) else { return false }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset - 1)
            return try handle.read(upToCount: 1)?.first == 0x0A
        } catch {
            return false
        }
    }

    func fileIdentity(at url: URL) -> FileIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = attributes[.systemFileNumber] as? NSNumber else { return nil }
        return FileIdentity(device: 0, inode: inode.uint64Value)
    }

    func fingerprint(of file: URL, endingAt offset: Int64) -> UInt64? {
        guard offset > 0, let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        let length = min(offset, 4_096)
        do {
            try handle.seek(toOffset: UInt64(offset - length))
            guard let data = try handle.read(upToCount: Int(length)), !data.isEmpty else { return nil }
            return data.reduce(UInt64(1_469_598_103_934_665_603)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
        } catch {
            return nil
        }
    }

    func cacheBoundaryMatches(_ file: LogFile, offset: UInt64, fingerprint: UInt64?) -> Bool {
        guard let fingerprint else { return false }
        return self.fingerprint(of: file.url, endingAt: Int64(offset)) == fingerprint
    }

}
