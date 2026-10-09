import SwiftUI

struct ClaudeConnectionView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Claude Code 연결").font(.headline)
            Text("Claude Code의 statusline에서 한도 숫자를 받아옵니다. 토큰 통계는 CLI 기록에서 따로 집계합니다.")
            Text("설정을 적용하면 settings.json을 백업합니다. 기존 statusline이 있으면 덮어쓰지 않습니다. 새 CLI 세션에서 첫 응답을 받은 후 갱신됩니다.")
                .foregroundStyle(.secondary)
            if let message = model.connectionMessage {
                Text(message).foregroundStyle(.secondary)
            }
            HStack {
                Button("닫기") { model.showConnection = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("연결 설정 적용") { model.installClaudeBridge() }.keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .padding(22)
        .frame(width: 380)
    }
}
