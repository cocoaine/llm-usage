import Foundation
import SwiftUI
import UsageCore

@MainActor
final class AppModel: ObservableObject {
    @Published var events: [UsageEvent] = []
    @Published var quotas: [Provider: QuotaSnapshot] = [:]
    @Published private(set) var isRefreshingQuota = false
    @Published private(set) var isScanningLogs = false
    @Published var refreshedAt: Date?
    @Published private var quotaMessage: String?
    @Published private var logMessage: String?
    @Published var period = 0
    @Published var showConnection = false
    @Published var connectionMessage: String?

    let home = FileManager.default.homeDirectoryForCurrentUser
    private let logScanInterval: TimeInterval = 5 * 60
    private let logScanner = LocalLogScanner()
    private var lastLogScanAt: Date?
    private var refreshLoop: Task<Void, Never>?

    var isRefreshing: Bool { isRefreshingQuota || isScanningLogs }
    var message: String? { quotaMessage ?? logMessage }

    deinit {
        refreshLoop?.cancel()
    }

    var claudeRoot: URL {
        if let path = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(".claude")
    }

    var codexRoot: URL {
        if let path = ProcessInfo.processInfo.environment["CODEX_HOME"], !path.isEmpty { return URL(fileURLWithPath: path) }
        return home.appendingPathComponent(".codex")
    }

    var selectedEvents: [UsageEvent] {
        let today = Calendar.current.startOfDay(for: Date())
        let since = period == 0 ? today : Calendar.current.date(byAdding: .day, value: -6, to: today)!
        return events.filter { $0.timestamp >= since && $0.timestamp <= Date() }
    }

    func total(for provider: Provider) -> TokenUsage {
        selectedEvents.filter { $0.provider == provider }.reduce(TokenUsage()) { $0 + $1.tokens }
    }

    func validWindow(_ window: QuotaWindow) -> Bool {
        window.resetsAt.map { $0 > Date() } ?? true
    }

    func remainingSummary(_ provider: Provider) -> String {
        guard let snapshot = quotas[provider], let window = snapshot.windows.first,
              validWindow(window) else { return "—" }
        let stale = Date().timeIntervalSince(snapshot.observedAt) > 300
        return "\(Int(window.remainingPercent.rounded()))%\(stale ? "~" : "")"
    }

    func menuSummary(_ provider: Provider) -> String {
        "\(provider.rawValue) \(remainingSummary(provider))"
    }

    /// The status-bar controller starts the app-wide loop at launch.
    /// Opening and closing the popover cannot pause quota refreshes.
    func startRefreshLoop() {
        guard refreshLoop == nil else { return }
        refreshLoop = Task { [weak self] in
            guard let self else { return }
            refresh(forceLogScan: true)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    break
                }
                guard !Task.isCancelled else { break }
                refresh(forceLogScan: false)
            }
        }
    }

    /// Account limits are refreshed every minute. JSONL token logs are read at
    /// launch, on manual refresh, and at most once per five minutes to avoid
    /// repeatedly walking a week's worth of CLI sessions.
    func refresh(forceLogScan: Bool = true) {
        let now = Date()
        let shouldScanLogs = forceLogScan
            || lastLogScanAt.map { now.timeIntervalSince($0) >= logScanInterval } ?? true
        refreshQuotas(now: now)
        if shouldScanLogs { refreshLogs(now: now) }
    }

    func installClaudeBridge() {
        do {
            guard let path = Bundle.main.executableURL else { return }
            try ClaudeBridge.install(executable: path, configDirectory: claudeRoot)
            connectionMessage = "연결 설정을 저장했습니다. 새 Claude Code 세션에서 응답을 받으면 한도가 표시됩니다."
        } catch {
            connectionMessage = error.localizedDescription
        }
    }
}

private extension AppModel {
    func refreshLogs(now: Date) {
        guard !isScanningLogs else { return }
        isScanningLogs = true
        let codexRoot = codexRoot, claudeRoot = claudeRoot
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now))!
        let scanner = logScanner
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                scanner.scan(codexRoot: codexRoot, claudeRoot: claudeRoot, since: since)
            }.value
            guard let self else { return }
            events = result.events
            lastLogScanAt = now
            logMessage = result.warnings.first
            for snapshot in result.quotas where !snapshot.windows.isEmpty {
                retainNewest(snapshot)
            }
            isScanningLogs = false
        }
    }

    func refreshQuotas(now: Date) {
        guard !isRefreshingQuota else { return }
        isRefreshingQuota = true
        // Claude writes only a non-empty snapshot, but retain the existing value
        // defensively if a partial or manually edited file decodes to no windows.
        if let claude = ClaudeBridge.read(), !claude.windows.isEmpty {
            retainNewest(claude)
        }
        refreshedAt = now
        guard let executable = CodexQuotaClient.locateExecutable() else {
            if quotas[.codex] == nil {
                quotaMessage = "Codex CLI를 찾지 못했습니다. 설치 경로를 확인하세요."
            } else {
                quotaMessage = "Codex CLI를 찾지 못해 마지막 \(quotas[.codex]!.source) 기록을 표시합니다."
            }
            isRefreshingQuota = false
            return
        }
        Task { [weak self] in
            let live = await Task.detached(priority: .utility) { () -> Result<QuotaSnapshot, Error> in
                Result { try CodexQuotaClient(executable: executable).fetch() }
            }.value
            guard let self else { return }
            switch live {
            case .success(let snapshot) where !snapshot.windows.isEmpty:
                quotas[.codex] = snapshot
                quotaMessage = nil
            case .success:
                quotaMessage = retainedCodexMessage(prefix: "Codex 계정 조회에 사용 가능한 한도가 없어")
            case .failure:
                quotaMessage = retainedCodexMessage(prefix: "Codex 계정 조회에 실패해")
            }
            refreshedAt = Date()
            isRefreshingQuota = false
        }
    }

    func retainNewest(_ snapshot: QuotaSnapshot) {
        if quotas[snapshot.provider].map({ $0.observedAt < snapshot.observedAt }) ?? true {
            quotas[snapshot.provider] = snapshot
        }
    }

    func retainedCodexMessage(prefix: String) -> String {
        guard let retained = quotas[.codex] else {
            return "\(prefix) 한도를 표시할 수 없습니다. CLI 로그인 상태를 확인하세요."
        }
        return "\(prefix) 마지막 \(retained.source) 기록을 표시합니다."
    }
}
