import AppKit
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: QuotaStore
    var onQuit: () -> Void
    var onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
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

    private var footer: some View {
        HStack(spacing: 10) {
            Text("更新于 \(Fmt.stamp(store.snapshot.updatedAt))")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("设置", action: onOpenSettings)
                .buttonStyle(.borderless).font(.system(size: 11))
            Button("退出", action: onQuit)
                .buttonStyle(.borderless).font(.system(size: 11))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
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
