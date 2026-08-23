import SwiftUI

/// First-run and later source configuration. This view intentionally appears
/// before any provider refresh so the user understands every keychain prompt
/// before macOS presents it.
struct SetupView: View {
    @ObservedObject var store: QuotaStore
    var onDone: () -> Void

    @State private var showCodex: Bool
    @State private var showClaude: Bool
    @State private var showOpenCode: Bool
    @State private var workspaceInput: String
    @State private var showDeepSeek: Bool
    @State private var deepSeekKey = ""
    @State private var feedback: FeedbackMessage?

    init(store: QuotaStore, onDone: @escaping () -> Void = {}) {
        self.store = store
        self.onDone = onDone
        _showCodex = State(initialValue: store.config.showCodex)
        _showClaude = State(initialValue: store.config.showClaude)
        _showOpenCode = State(initialValue: store.config.showOpenCode)
        _workspaceInput = State(initialValue: store.config.opencodeWorkspaceID)
        _showDeepSeek = State(initialValue: store.config.showDeepSeek)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                intro
                permissionNotice

                SourceToggleRow(tag: "Cx", title: "Codex",
                                detail: "安装并登录 codex CLI 后即可读取",
                                isOn: $showCodex)
                SourceToggleRow(tag: "Cl", title: "Claude",
                                detail: "登录 Claude Code 后即可读取",
                                isOn: $showClaude)

                sourceCard(tag: "OC", title: "OpenCode", isOn: $showOpenCode) {
                    TextField("wrk_… 或完整工作区 URL", text: $workspaceInput)
                        .textFieldStyle(.roundedBorder)
                    Text("可直接粘贴 opencode.ai/workspace/<ID>/go，App 会自动提取 ID。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                sourceCard(tag: "DS", title: "DeepSeek", isOn: $showDeepSeek) {
                    SecureField("输入 API Key；留空则继续使用现有钥匙串条目",
                                text: $deepSeekKey)
                        .textFieldStyle(.roundedBorder)
                    Text("Key 只写入 macOS 钥匙串，不会保存到 config.json。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if let feedback {
                    Label(feedback.text,
                          systemImage: feedback.tone == .error
                            ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(feedback.tone.color)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Spacer()
                    Button(store.config.setupCompleted ? "保存设置" : "保存并开始读取") {
                        save()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
            }
            .padding(12)
        }
        .frame(maxHeight: 540)
        .tint(QuotaTheme.brand)
    }

    private var intro: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(QuotaTheme.brand.opacity(0.14))
                Image(systemName: store.config.setupCompleted ? "slider.horizontal.3" : "hand.wave.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(QuotaTheme.brand)
            }
            .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 3) {
                Text(store.config.setupCompleted ? "数据源设置" : "欢迎使用 AI Quota")
                    .font(.system(size: 14, weight: .semibold))
                Text(store.config.setupCompleted
                     ? "启用需要的来源，关闭不使用的来源。"
                     : "先完成一次简单设置，再开始读取额度。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var permissionNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("首次授权提示", systemImage: "key.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(QuotaTheme.brand)
            Text("点击开始后，已启用来源最多会请求 Chrome Safe Storage、Claude Code-credentials 和 DeepSeek 钥匙串访问。请核对名称后选择允许。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(9)
        .background(QuotaTheme.brand.opacity(0.075),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private func sourceCard<Content: View>(tag: String, title: String,
                                           isOn: Binding<Bool>,
                                           @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SourceToggleRow(tag: tag, title: title,
                            detail: isOn.wrappedValue ? "已启用" : "可选",
                            isOn: isOn)
            if isOn.wrappedValue {
                content()
                    .padding(.leading, 35)
            }
        }
        .padding(9)
        .background(QuotaTheme.cardFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(QuotaTheme.cardStroke, lineWidth: 0.65)
        }
    }

    private func save() {
        let workspaceID = Self.workspaceID(from: workspaceInput)
        if showOpenCode && !workspaceID.hasPrefix("wrk_") {
            feedback = FeedbackMessage(
                text: "OpenCode 需要 wrk_ 开头的 ID，或包含 /workspace/<ID>/ 的完整 URL。",
                tone: .error)
            return
        }

        do {
            try store.applySetup(showCodex: showCodex,
                                 showClaude: showClaude,
                                 showOpenCode: showOpenCode,
                                 workspaceID: workspaceID,
                                 showDeepSeek: showDeepSeek,
                                 deepSeekKey: deepSeekKey)
            deepSeekKey = ""
            feedback = FeedbackMessage(text: "设置已保存，开始读取额度。", tone: .success)
            onDone()
        } catch {
            feedback = FeedbackMessage(text: error.localizedDescription, tone: .error)
        }
    }

    /// Accepts either `wrk_…` or a full/partial OpenCode workspace URL.
    static func workspaceID(from input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("wrk_") { return trimmed }

        let candidate = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        if let url = URL(string: candidate),
           let index = url.pathComponents.firstIndex(of: "workspace"),
           url.pathComponents.indices.contains(index + 1) {
            return url.pathComponents[index + 1]
        }
        return trimmed
    }
}

private struct SourceToggleRow: View {
    var tag: String
    var title: String
    var detail: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(tag)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(QuotaTheme.brand)
                .frame(width: 27, height: 20)
                .background(QuotaTheme.brand.opacity(0.13),
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Text(detail).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .controlSize(.small)
        }
    }
}
