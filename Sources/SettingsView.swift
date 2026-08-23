import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @State private var draft: Config
    @State private var launchAtLogin: Bool
    @State private var status: String?

    init(store: QuotaStore) {
        self.store = store
        _draft = State(initialValue: store.config)
        _launchAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
    }

    var body: some View {
        Form {
            Section("OpenCode") {
                TextField("工作区 ID", text: $draft.opencodeWorkspaceID, prompt: Text("wrk_…"))
                Toggle("显示 OpenCode", isOn: $draft.showOpenCode)
                Text("额度读自 Chrome 的登录会话，需要在浏览器里保持登录。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("DeepSeek") {
                TextField("钥匙串服务名", text: $draft.deepseekKeychainService)
                TextField("钥匙串账户", text: $draft.deepseekKeychainAccount)
                Toggle("显示 DeepSeek", isOn: $draft.showDeepSeek)
                Text("用官方 /user/balance 接口读余额，也可改用环境变量 DEEPSEEK_API_KEY。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Codex") {
                Toggle("显示 Codex", isOn: $draft.showCodex)
                Text("通过本地 codex app-server 读取，不经手任何凭证。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("通用") {
                Stepper("刷新间隔：\(draft.refreshMinutes) 分钟",
                        value: $draft.refreshMinutes, in: 1...240)
                Toggle("开机自动启动", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        toggleLaunchAtLogin(enabled)
                    }
            }
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("保存并刷新") { save() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding(.vertical, 6)
    }

    private func save() {
        store.config = draft
        do {
            try draft.save()
            store.scheduleTimer()
            Task { await store.refresh() }
            status = "已保存"
        } catch {
            status = "保存失败：\(error.localizedDescription)"
        }
    }

    private func toggleLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            status = "开机启动设置失败：\(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
