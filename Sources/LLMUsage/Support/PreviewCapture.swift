import AppKit
import SwiftUI
import UsageCore

/// Renders the real panel with synthetic numeric values for visual checks.
@MainActor
enum PreviewCapture {
    static func writePanelPNG(to url: URL) throws {
        _ = NSApplication.shared
        let model = AppModel()
        let now = Date()
        model.period = 1
        model.quotas = [
            .codex: QuotaSnapshot(provider: .codex, windows: [
                QuotaWindow(label: "5시간 한도", usedPercent: 28, resetsAt: now.addingTimeInterval(90 * 60)),
                QuotaWindow(label: "7일 한도", usedPercent: 62, resetsAt: now.addingTimeInterval(3 * 86_400))
            ], observedAt: now, source: "계정 조회"),
            .claude: QuotaSnapshot(provider: .claude, windows: [
                QuotaWindow(label: "5시간 한도", usedPercent: 41, resetsAt: now.addingTimeInterval(48 * 60)),
                QuotaWindow(label: "7일 한도", usedPercent: 35, resetsAt: now.addingTimeInterval(5 * 86_400))
            ], observedAt: now, source: "CLI statusline")
        ]
        model.events = [
            UsageEvent(id: "preview-codex", provider: .codex, model: "gpt-5-codex", timestamp: now, tokens: TokenUsage(input: 42_000, output: 8_200, cacheRead: 16_000)),
            UsageEvent(id: "preview-claude", provider: .claude, model: "claude-sonnet-4", timestamp: now, tokens: TokenUsage(input: 31_000, output: 6_400, cacheRead: 11_000, cacheWrite: 2_000))
        ]
        model.refreshedAt = now

        let view = NSHostingView(rootView: UsagePanel(model: model).background(Color(nsColor: .windowBackgroundColor)))
        view.frame = NSRect(x: 0, y: 0, width: 380, height: 1)
        view.layoutSubtreeIfNeeded()
        view.frame.size.height = ceil(max(view.fittingSize.height, 1))
        view.layoutSubtreeIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw CollectorError.unavailable("패널 미리보기를 렌더링하지 못했습니다.")
        }
        view.cacheDisplay(in: view.bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else {
            throw CollectorError.unavailable("패널 PNG를 만들지 못했습니다.")
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url, options: .atomic)
    }
}
