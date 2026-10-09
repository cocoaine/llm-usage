import Foundation
import Darwin

public enum CollectorError: LocalizedError {
    case unavailable(String)
    public var errorDescription: String? {
        switch self { case .unavailable(let message): message }
    }
}

public struct CodexQuotaClient: Sendable {
    public var executable: URL
    public var timeout: TimeInterval
    public init(executable: URL, timeout: TimeInterval = 15) {
        self.executable = executable; self.timeout = timeout
    }

    public func fetch() throws -> QuotaSnapshot {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        // Close the parent's copy of the child's pipe end so EOF remains observable.
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        defer {
            try? input.fileHandleForWriting.close()
            stopAndReap(process)
            try? output.fileHandleForReading.close()
        }
        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "llm_usage", "version": "0.1.0"]
        ]])
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = Data()
        while Date() < deadline {
            var fd = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = poll(&fd, 1, 200)
            if ready < 0 { throw CollectorError.unavailable("Codex 응답을 읽지 못했습니다.") }
            if ready == 0 { continue }
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { throw CollectorError.unavailable("Codex App Server가 종료되었습니다. CLI 로그인을 확인하세요.") }
            buffer.append(chunk)
            guard buffer.count < 4_000_000 else { throw CollectorError.unavailable("Codex 응답 크기가 예상보다 큽니다.") }
            while let newline = buffer.firstIndex(of: 10) {
                let line = buffer[..<newline]; buffer.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                      let id = object["id"] as? Int else { continue }
                if object["error"] != nil {
                    throw CollectorError.unavailable("Codex 한도를 조회하지 못했습니다. codex login 상태를 확인하세요.")
                }
                if id == 1 {
                    try send(["method": "initialized"])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if id == 2, let result = object["result"] as? [String: Any] {
                    return try Self.parse(result: result)
                }
            }
        }
        throw CollectorError.unavailable("Codex 한도 조회 시간이 초과되었습니다.")
    }

    private func stopAndReap(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let deadline = Date().addingTimeInterval(0.5)
        while process.isRunning, Date() < deadline {
            usleep(10_000)
        }
        if process.isRunning {
            _ = kill(process.processIdentifier, SIGKILL)
        }
        // SIGKILL guarantees this does not leave a child or zombie behind.
        if process.isRunning { process.waitUntilExit() }
    }

    public static func parse(result: [String: Any], observedAt: Date = Date()) throws -> QuotaSnapshot {
        let buckets = result["rateLimitsByLimitId"] as? [String: [String: Any]]
        guard let snapshot = buckets?["codex"] ?? result["rateLimits"] as? [String: Any] else {
            throw CollectorError.unavailable("Codex 한도 데이터가 없습니다.")
        }
        var windows: [QuotaWindow] = []
        for key in ["primary", "secondary"] {
            guard let window = snapshot[key] as? [String: Any],
                  let percent = window["usedPercent"] as? NSNumber,
                  percent.doubleValue.isFinite, (0...100).contains(percent.doubleValue) else { continue }
            let minutes = (window["windowDurationMins"] as? NSNumber)?.intValue
            let label: String
            if let minutes, minutes > 0 {
                label = minutes % 1440 == 0 ? "\(minutes / 1440)일 한도" : minutes % 60 == 0 ? "\(minutes / 60)시간 한도" : "\(minutes)분 한도"
            } else { label = key == "primary" ? "단기 한도" : "장기 한도" }
            let reset = (window["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(QuotaWindow(label: label, usedPercent: percent.doubleValue, resetsAt: reset))
        }
        if let limit = snapshot["individualLimit"] as? [String: Any],
           let remaining = limit["remainingPercent"] as? NSNumber,
           (0...100).contains(remaining.doubleValue) {
            let reset = (limit["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            windows.append(QuotaWindow(label: "크레딧 한도", usedPercent: 100 - remaining.doubleValue, resetsAt: reset))
        }
        return QuotaSnapshot(provider: .codex, windows: windows, observedAt: observedAt, source: "계정 조회")
    }

    public static func locateExecutable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL? {
        let paths = [home.appendingPathComponent(".local/bin/codex").path,
                     "/opt/homebrew/bin/codex", "/usr/local/bin/codex"] +
            (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/codex" }
        return paths.first(where: FileManager.default.isExecutableFile(atPath:)).map { URL(fileURLWithPath: $0) }
    }
}
