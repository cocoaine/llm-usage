import SwiftUI
import UsageCore

struct TokenSummaryView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack {
            Text("토큰 사용량").fontWeight(.semibold)
            Spacer()
            Picker("집계 기간", selection: $model.period) {
                Text("오늘").tag(0)
                Text("최근 7일").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(width: 154)
        }
        .padding(.top, 16)

        Text("이 Mac의 CLI 기록 · 로컬 날짜 기준")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.top, 6)

        VStack(spacing: 10) {
            ForEach(Provider.allCases) { provider in
                let tokens = model.total(for: provider)
                HStack(alignment: .firstTextBaseline) {
                    Text(provider.rawValue)
                    Spacer()
                    Text(model.selectedEvents.contains(where: { $0.provider == provider }) ? tokenText(tokens.total) : "—")
                        .monospacedDigit()
                        .fontWeight(.medium)
                }
            }
            let total = model.selectedEvents.reduce(TokenUsage()) { $0 + $1.tokens }
            if !model.selectedEvents.isEmpty {
                HStack(spacing: 14) {
                    TokenColumn(label: "입력", value: total.input)
                    TokenColumn(label: "출력", value: total.output)
                    TokenColumn(label: "캐시", value: total.cacheRead + total.cacheWrite)
                }
                .padding(.top, 4)
            } else {
                Text(model.isScanningLogs ? "토큰 기록을 읽는 중입니다." : "선택한 기간에 수집된 기록이 없습니다.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 14)
    }
}

private struct TokenColumn: View {
    let label: String
    let value: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).foregroundStyle(.secondary)
            Text(tokenText(value)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }
        .font(.system(size: 11))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
