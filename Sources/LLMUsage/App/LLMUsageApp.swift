import AppKit
import SwiftUI
import UsageCore

@main
struct LLMUsageApp: App {
    @StateObject private var model = AppModel()
    private let screenshotPath: String?

    init() {
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "--screenshot"), args.indices.contains(index + 1) {
            screenshotPath = args[index + 1]
        } else {
            screenshotPath = nil
        }
        if args.contains("--capture-claude") {
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
        if args.contains("--diagnose") {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let env = ProcessInfo.processInfo.environment
            let codex = env["CODEX_HOME"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".codex")
            let claude = env["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) } ?? home.appendingPathComponent(".claude")
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

    var body: some Scene {
        MenuBarExtra {
            UsagePanel(model: model)
        } label: {
            Text(model.menuSummary(.codex) + " · " + model.menuSummary(.claude))
                .monospacedDigit()
                .task {
                    if let screenshotPath {
                        do {
                            try PreviewCapture.writePanelPNG(to: URL(fileURLWithPath: screenshotPath))
                        } catch {
                            print(error.localizedDescription)
                        }
                        NSApplication.shared.terminate(nil)
                    } else {
                        model.startRefreshLoop()
                    }
                }
        }
        .menuBarExtraStyle(.window)
    }
}
