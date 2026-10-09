import SwiftUI
import UsageCore

struct ModelTotal: Identifiable {
    let provider: Provider
    let model: String
    let tokens: TokenUsage
    var id: String { provider.rawValue + "/" + model }
}

struct ModelUsageView: View {
    let events: [UsageEvent]

    private var totals: [ModelTotal] {
        let grouped = Dictionary(grouping: events) { $0.provider.rawValue + "/" + $0.model }
        return grouped.values.compactMap { values in
            guard let first = values.first else { return nil }
            return ModelTotal(
                provider: first.provider,
                model: first.model,
                tokens: values.reduce(TokenUsage()) { $0 + $1.tokens }
            )
        }
        .sorted { $0.tokens.total == $1.tokens.total ? $0.id < $1.id : $0.tokens.total > $1.tokens.total }
    }

    var body: some View {
        if !totals.isEmpty {
            Divider()
            Text("모델별 사용량").fontWeight(.semibold).padding(.top, 14)
            ScrollView {
                VStack(spacing: 9) {
                    ForEach(totals) { row in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(row.model).lineLimit(1).truncationMode(.middle).help(row.model)
                                Text(row.provider.rawValue).font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 12)
                            Text(tokenText(row.tokens.total)).monospacedDigit()
                        }
                    }
                }
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 145)
        }
    }
}
