import Foundation

public enum ClaudeBridge {
    public static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/LLMUsage", isDirectory: true)
    }
    public static var snapshotURL: URL { directory.appendingPathComponent("claude-quota.json") }

    /// Keep only allowance measurements, never session content or credentials.
    public static func parse(_ data: Data, observedAt: Date = Date()) throws -> QuotaSnapshot {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CollectorError.unavailable("Claude 데이터 형식을 확인하세요.")
        }
        let limits = object["rate_limits"] as? [String: Any] ?? [:]
        var windows: [QuotaWindow] = []
        for (key, label) in [("five_hour", "5시간 한도"), ("seven_day", "7일 한도")] {
            guard let window = limits[key] as? [String: Any],
                  let used = window["used_percentage"] as? NSNumber,
                  used.doubleValue.isFinite, (0...100).contains(used.doubleValue) else { continue }
            let reset = (window["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(QuotaWindow(label: label, usedPercent: used.doubleValue, resetsAt: reset))
        }
        return QuotaSnapshot(provider: .claude, windows: windows, observedAt: observedAt, source: "CLI statusline")
    }

    public static func capture(_ data: Data, at url: URL = snapshotURL) throws -> QuotaSnapshot {
        let snapshot = try parse(data)
        // An empty payload (before a response/API-key account) must not overwrite valid data.
        if !snapshot.windows.isEmpty {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return snapshot
    }

    public static func read(at url: URL = snapshotURL) -> QuotaSnapshot? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    public static func shellQuote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    public static func install(executable: URL, configDirectory: URL) throws {
        let fm = FileManager.default
        let settingsURL = configDirectory.appendingPathComponent("settings.json")
        var settings: [String: Any] = [:]
        var original: Data?
        var existingPermissions: NSNumber?
        if fm.fileExists(atPath: settingsURL.path) {
            original = try Data(contentsOf: settingsURL)
            existingPermissions = try? fm.attributesOfItem(atPath: settingsURL.path)[.posixPermissions] as? NSNumber
            guard let decoded = try JSONSerialization.jsonObject(with: original!) as? [String: Any] else {
                throw CollectorError.unavailable("Claude settings.json 형식이 올바르지 않습니다.")
            }
            settings = decoded
        }
        let command = shellQuote(executable.path) + " --capture-claude"
        if let existing = settings["statusLine"], !(existing is NSNull) {
            if let existing = existing as? [String: Any], existing["command"] as? String == command { return }
            throw CollectorError.unavailable("기존 statusline 설정이 있습니다. 기존 명령에 LLM Usage 수집을 연결해야 합니다. README를 확인하세요.")
        }
        try fm.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        if let original {
            let backup = configDirectory.appendingPathComponent("settings.llmusage-backup-\(UUID().uuidString).json")
            try original.write(to: backup, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        settings["statusLine"] = ["type": "command", "command": command]
        try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]).write(to: settingsURL, options: .atomic)
        try fm.setAttributes([.posixPermissions: existingPermissions ?? 0o600], ofItemAtPath: settingsURL.path)
    }
}
