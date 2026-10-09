import AppKit
import SwiftUI
import UsageCore

struct UsagePanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader
            Text("계정 한도 · 남은 사용량")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(Provider.allCases) { provider in
                    QuotaSectionView(provider: provider, snapshot: model.quotas[provider], isWindowValid: model.validWindow)
                }
            }
            .padding(.vertical, 18)

            Divider()
            TokenSummaryView(model: model)
            ModelUsageView(events: model.selectedEvents)
            panelFooter
        }
        .font(.system(size: 13))
        .padding(18)
        .frame(width: 380)
        .sheet(isPresented: $model.showConnection) {
            ClaudeConnectionView(model: model)
        }
    }

    private var panelHeader: some View {
        HStack {
            Text("LLM Usage").font(.system(size: 17, weight: .semibold))
            Spacer()
            if model.isRefreshing {
                ProgressView().controlSize(.small).accessibilityLabel("사용량 갱신 중")
            }
            Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .disabled(model.isRefreshing)
                .help("사용량 새로고침")
                .accessibilityLabel("사용량 새로고침")
        }
    }

    private var panelFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let message = model.message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            if let refreshedAt = model.refreshedAt {
                Text("마지막 갱신 \(refreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            Divider().padding(.top, 14)
            HStack {
                Button("Claude 연결…") { model.showConnection = true }.buttonStyle(.link)
                Spacer()
                Button("종료") { NSApplication.shared.terminate(nil) }.buttonStyle(.link)
            }
            .font(.system(size: 11))
            .padding(.top, 10)
        }
    }
}
