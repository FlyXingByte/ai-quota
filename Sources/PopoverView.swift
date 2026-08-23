import AppKit
import ServiceManagement
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: QuotaStore
    var onQuit: () -> Void

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var note: String?

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
        .frame(width: 340)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.67percent")
                .foregroundStyle(.tint)
            Text("AI 配额").font(.system(size: 13, weight: .semibold))
            Spacer()
            if store.snapshot.refreshing {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
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
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.snapshot.cards) { card in
                        CardView(card: card)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .frame(maxHeight: 460)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Text(note ?? "更新于 \(Fmt.stamp(store.snapshot.updatedAt))")
                .font(.system(size: 10))
                .foregroundStyle(note == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
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
                        note = "菜单栏改为显示：\(chosen.title)"
                    } catch {
                        note = "设置保存失败：\(error.localizedDescription)"
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
            note = enabled ? "已加入登录项" : "已移出登录项"
        } catch {
            note = "登录项设置失败：\(error.localizedDescription)"
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
        note = "改完保存，下次刷新自动生效"
    }
}

private struct CardView: View {
    let card: ProviderCard

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Text(card.name).font(.system(size: 12, weight: .semibold))
                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                Spacer()
                if let link = card.link {
                    Button {
                        NSWorkspace.shared.open(link)
                    } label: {
                        Image(systemName: "arrow.up.forward.square")
                            .font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .help("在浏览器里打开")
                }
            }

            if let error = card.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(card.windows) { window in
                WindowRow(window: window)
            }

            ForEach(card.notes, id: \.self) { note in
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WindowRow: View {
    let window: QuotaWindow

    private var color: Color {
        guard window.remainingPercent != nil else { return .secondary }
        if window.isCritical { return .red }
        if window.isWarning { return .orange }
        return .green
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(window.label)
                    .font(.system(size: 11))
                    .lineLimit(1)
                Spacer()
                if let remaining = window.remainingPercent {
                    // Labelled explicitly: a bare percentage next to a quota is
                    // ambiguous about which direction it counts.
                    Text("剩余 \(Int(remaining))%")
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(color)
                } else if let value = window.value {
                    Text(value)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
            }
            if let remaining = window.remainingPercent {
                // The bar drains as the quota is spent.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.secondary.opacity(0.15))
                        Capsule().fill(color)
                            .frame(width: max(2, geo.size.width * min(1, remaining / 100)))
                    }
                }
                .frame(height: 4)
            }
            if let reset = Fmt.relative(window.resetsAt) {
                Text(reset)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
