import AppKit
import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: QuotaStore
    var onQuit: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var feedback: FeedbackMessage?

    private var needsWorkspaceID: Bool {
        store.config.showOpenCode && store.config.opencodeWorkspaceID.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            if needsWorkspaceID {
                Divider()
                workspaceHint
            }
            Divider()
            footer
        }
        .frame(width: 372)
        .tint(QuotaTheme.brand)
    }

    private var header: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().fill(QuotaTheme.brand.opacity(0.14))
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(QuotaTheme.brand)
            }
            .frame(width: 23, height: 23)

            VStack(alignment: .leading, spacing: 0) {
                Text("AI Quota")
                    .font(.system(size: 13, weight: .semibold))
                Text("额度概览")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if store.snapshot.refreshing {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.75)
                    .frame(width: 24, height: 24)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .background(Color.primary.opacity(0.055), in: Circle())
                .contentShape(Circle())
                .help("立即刷新")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if store.snapshot.cards.isEmpty {
            HStack {
                Spacer()
                VStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("正在读取…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.vertical, 28)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(store.snapshot.cards) { card in
                        CardView(card: card)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 490)
        }
    }

    /// Without a workspace ID the OpenCode card simply never appears, which
    /// looks like a bug rather than a missing setting. Say so, and offer the
    /// one place that setting now lives.
    private var workspaceHint: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("OpenCode 还没配工作区 ID")
                    .font(.system(size: 11))
                Button("打开配置文件…") { openConfigFile() }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10))
            }
            Spacer()
        }
        .padding(10)
        .background(QuotaTheme.brand.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(feedback?.text ?? "更新于 \(Fmt.stamp(store.snapshot.updatedAt))")
                .font(.system(size: 10))
                .foregroundStyle(feedback?.tone.color ?? .secondary)
                .lineLimit(1)
            Spacer()
            Menu {
                Button("立即刷新") { Task { await store.refresh() } }
                Divider()
                // A Picker inside a Menu renders as a submenu with a checkmark
                // on the active row — the native way to offer this choice.
                Picker("菜单栏显示", selection: menuBarSource) {
                    ForEach(MenuBarSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
                Divider()
                Toggle("开机自动启动", isOn: $launchAtLogin)
                Button("打开配置文件…") { openConfigFile() }
                Divider()
                Button("退出 AI Quota", action: onQuit)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多")
            .onChange(of: launchAtLogin) { _, enabled in
                setLaunchAtLogin(enabled)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var menuBarSource: Binding<MenuBarSource> {
        Binding(get: { store.config.menuBar },
                set: { chosen in
                    do {
                        try store.setMenuBarSource(chosen)
                        feedback = FeedbackMessage(text: "菜单栏显示：\(chosen.title)",
                                                   tone: .success)
                    } catch {
                        feedback = FeedbackMessage(text: "设置保存失败：\(error.localizedDescription)",
                                                   tone: .error)
                    }
                })
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            feedback = FeedbackMessage(text: enabled ? "已加入登录项" : "已移出登录项",
                                       tone: .success)
        } catch {
            feedback = FeedbackMessage(text: "登录项设置失败：\(error.localizedDescription)",
                                       tone: .error)
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    /// config.json is the whole settings surface now, so this has to work even
    /// on a fresh install where the file has not been written yet.
    private func openConfigFile() {
        if !FileManager.default.fileExists(atPath: Config.fileURL.path) {
            try? store.config.save()
        }
        if !NSWorkspace.shared.open(Config.fileURL) {
            NSWorkspace.shared.activateFileViewerSelecting([Config.fileURL])
        }
        feedback = FeedbackMessage(text: "保存配置后，下次刷新自动生效", tone: .neutral)
    }
}

private struct CardView: View {
    let card: ProviderCard

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text(card.tag)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(QuotaTheme.brand)
                    .frame(minWidth: 25, minHeight: 20)
                    .padding(.horizontal, 2)
                    .background(QuotaTheme.brand.opacity(0.13),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(card.name)
                    .font(.system(size: 12.5, weight: .semibold))
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.11), in: Capsule())
                }
                Spacer()
                if let link = card.link {
                    Button {
                        NSWorkspace.shared.open(link)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
                    .help("在浏览器里打开")
                }
            }

            if let error = card.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            ForEach(card.windows) { window in
                WindowRow(window: window)
            }

            ForEach(card.notes, id: \.self) { note in
                NoteRow(text: note)
            }
        }
        .padding(11)
        .background(QuotaTheme.cardFill,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(QuotaTheme.cardStroke, lineWidth: 0.65)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct NoteRow: View {
    let text: String

    private var needsAttention: Bool {
        text.contains("未启用") || text.contains("已用尽")
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: needsAttention ? "pause.circle.fill" : "info.circle")
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(needsAttention ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
    }
}

private struct WindowRow: View {
    let window: QuotaWindow

    private var color: Color {
        guard let remaining = window.remainingPercent else { return .secondary }
        return QuotaTheme.quotaColor(for: remaining)
    }

    private var statusSymbol: String? {
        if window.isCritical { return "exclamationmark.octagon.fill" }
        if window.isWarning { return "exclamationmark.triangle.fill" }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(window.label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer()
                if let remaining = window.remainingPercent {
                    HStack(spacing: 4) {
                        if let statusSymbol {
                            Image(systemName: statusSymbol)
                                .font(.system(size: 9))
                        }
                        Text("剩余 \(Int(remaining))%")
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    }
                    .foregroundStyle(color)
                } else if let value = window.value {
                    Text(value)
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.065), in: Capsule())
                }
            }
            if let remaining = window.remainingPercent {
                // The bar drains as the quota is spent.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(QuotaTheme.track)
                        Capsule().fill(color)
                            .frame(width: max(3, geo.size.width * min(1, remaining / 100)))
                    }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.25), value: remaining)
                .accessibilityLabel("\(window.label)，剩余 \(Int(remaining))%")
            }
            if let reset = Fmt.relative(window.resetsAt) {
                Text(reset)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
