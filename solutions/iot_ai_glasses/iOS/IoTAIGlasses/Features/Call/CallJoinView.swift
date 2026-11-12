import SwiftUI

struct CallJoinView: View {
    @Environment(AppState.self) private var state
    @Environment(AppRouter.self) private var router
    @AppStorage("callRoomId") private var roomId = ""
    @AppStorage("callUserId") private var userId = ""
    @FocusState private var focused: Field?

    private enum Field {
        case room
        case user
    }

    var body: some View {
        FlowScreen {
            PageHeader(title: "语音通话", backLabel: "返回首页", onBack: router.pop)
        } content: {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        field(title: "房间号", placeholder: "输入房间号", text: $roomId, field: .room)
                        field(title: "用户 ID", placeholder: "输入你的用户 ID", text: $userId, field: .user)
                        Text("对方进入同一房间号即可通话。纯数字按数字房间号进房，否则按字符串房间号。")
                            .font(AppFont.caption)
                            .lineSpacing(3)
                            .foregroundStyle(Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .surface(radius: 22)

                    SettingsGroup {
                        SettingRow(icon: .glasses, title: "眼镜通话") {
                            if state.isConnected {
                                StatusDot(text: "已连接")
                            } else {
                                Button("连接眼镜") { state.reconnect() }
                                    .buttonStyle(.pill)
                            }
                        }
                    }
                }
                .padding(1)
                .scrollShadowProbe()
            }
            .topScrollShadow()
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        } footer: {
            VStack(spacing: 12) {
                if let reason = blockedReason {
                    Text(reason)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.danger)
                }
                Button {
                    join()
                } label: {
                    HStack(spacing: 9) {
                        AppIconView(.call, size: 20)
                        Text(state.session?.kind == .call ? "返回通话" : "进入房间")
                    }
                }
                .buttonStyle(.primary)
                .disabled(state.session?.kind != .call && blockedReason != nil)
            }
            .padding(.top, 24)
        }
        .onAppear {
            if userId.isEmpty { userId = TRTCCredentials.userId }
        }
    }

    private func field(title: String, placeholder: String, text: Binding<String>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppFont.captionMedium)
                .foregroundStyle(Palette.textSecondary)
            TextField(placeholder, text: text)
                .font(AppFont.bodyMedium)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(field == .room ? .next : .go)
                .focused($focused, equals: field)
                .onSubmit {
                    if field == .room { focused = .user } else { join() }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Palette.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        }
    }

    private var trimmedRoom: String { roomId.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUser: String { userId.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var blockedReason: String? {
        if let reason = state.captureBlocker { return reason }
        if trimmedRoom.isEmpty { return "请输入房间号" }
        if trimmedUser.isEmpty { return "请输入用户 ID" }
        return nil
    }

    private func join() {
        focused = nil
        if state.session?.kind == .call {
            router.push(.live(.call))
            return
        }
        guard blockedReason == nil else { return }
        if state.session != nil {
            state.dialog = .conflict
            return
        }
        roomId = trimmedRoom
        userId = trimmedUser
        if state.startCall(roomId: trimmedRoom, userId: trimmedUser) {
            router.push(.live(.call))
        }
    }
}
