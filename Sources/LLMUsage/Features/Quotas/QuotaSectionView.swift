import SwiftUI
import UsageCore

struct QuotaSectionView: View {
    let provider: Provider
    let snapshot: QuotaSnapshot?
    let isWindowValid: (QuotaWindow) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(provider.rawValue).fontWeight(.semibold)
                Spacer()
                if let snapshot {
                    Text(snapshot.source).font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let snapshot, !snapshot.windows.isEmpty {
                ForEach(Array(snapshot.windows.enumerated()), id: \.offset) { _, window in
                    quotaWindow(window)
                }
                Text(collectionText(for: snapshot))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                emptyQuota
            }
        }
    }

    @ViewBuilder
    private func quotaWindow(_ window: QuotaWindow) -> some View {
        let valid = isWindowValid(window)
        HStack {
            Text(window.label).foregroundStyle(.secondary)
            Spacer()
            Text(valid ? "\(Int(window.remainingPercent.rounded()))% 남음" : "갱신 필요")
                .monospacedDigit()
        }
        .font(.system(size: 12))
        if valid {
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(window.remainingPercent <= 15 ? .orange : .blue)
                .accessibilityLabel("\(provider.rawValue) \(window.label)")
                .accessibilityValue("\(Int(window.remainingPercent))퍼센트 남음")
        }
        if let reset = window.resetsAt {
            Text(reset > Date()
                 ? "초기화 \(reset.formatted(.relative(presentation: .named))) · \(reset.formatted(date: .abbreviated, time: .shortened))"
                 : "초기화 시각이 지나 새 기록이 필요합니다.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyQuota: some View {
        HStack {
            Text(provider == .claude ? "CLI 연결 후 한도가 표시됩니다." : "한도 정보를 기다리고 있습니다.")
                .foregroundStyle(.secondary)
            Spacer()
            Text("—").monospacedDigit()
        }
        .font(.system(size: 12))
    }

    private func collectionText(for snapshot: QuotaSnapshot) -> String {
        let stale = Date().timeIntervalSince(snapshot.observedAt) > 300
        return "수집 \(snapshot.observedAt.formatted(date: .omitted, time: .shortened))\(stale ? " · 오래된 기록" : "")"
    }
}
