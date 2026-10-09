import AppKit
import UsageCore

@main
@MainActor
final class LLMUsageApp: NSObject {
    static func main() {
        let arguments = CommandLine.arguments
        if arguments.contains("--capture-claude") {
            captureClaudeStatusline()
        }
        if arguments.contains("--diagnose") {
            printDiagnosticSummary()
        }

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let statusBarController = StatusBarController()
        application.delegate = statusBarController
        withExtendedLifetime(statusBarController) {
            application.run()
        }
    }

    private static func captureClaudeStatusline() -> Never {
        do {
            let input = FileHandle.standardInput.readDataToEndOfFile()
            let snapshot = try ClaudeBridge.capture(input)
            let text = snapshot.windows.map { "\($0.label) \(Int($0.remainingPercent.rounded()))% 남음" }.joined(separator: " · ")
            print(text.isEmpty ? "Claude" : "Claude · " + text)
            exit(0)
        } catch {
            // Keep statusline output short and never echo its input.
            print("Claude · LLM Usage 연결 확인 필요")
            exit(1)
        }
    }

    private static func printDiagnosticSummary() -> Never {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let environment = ProcessInfo.processInfo.environment
        let codex = environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
        let claude = environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
        let since = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: Date()))!
        let result = LocalLogScanner().scan(codexRoot: codex, claudeRoot: claude, since: since)
        for provider in Provider.allCases {
            let events = result.events.filter { $0.provider == provider && $0.timestamp <= Date() }
            let total = events.reduce(TokenUsage()) { $0 + $1.tokens }
            print("\(provider.rawValue): \(events.count) events, \(total.total) tokens, \(Set(events.map(\.model)).count) models")
            if let quota = result.quotas.filter({ $0.provider == provider }).max(by: { $0.observedAt < $1.observedAt }) {
                print("\(provider.rawValue) quota: " + quota.windows.map { "\($0.label) \(Int($0.remainingPercent))% remaining" }.joined(separator: ", "))
            }
        }
        for warning in result.warnings { print(warning) }
        exit(0)
    }
}
