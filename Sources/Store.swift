import Combine
import Foundation

/// Owns the snapshot and the refresh schedule. Providers run concurrently so one
/// slow source never holds up the rest.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var config: Config

    private var timer: Timer?

    init(config: Config = .load()) {
        self.config = config
    }

    func start() {
        Task { await refresh() }
        scheduleTimer()
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, config.refreshMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh() async {
        guard !snapshot.refreshing else { return }
        reloadConfig()
        snapshot.refreshing = true
        let providers = config.providers

        let cards = await withTaskGroup(of: (Int, ProviderCard).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await provider.fetch()) }
            }
            var collected: [(Int, ProviderCard)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        snapshot.cards = cards
        snapshot.updatedAt = Date()
        snapshot.refreshing = false
        logRefresh()
    }

    /// Records the result of each refresh. Keychain and cookie access behave
    /// differently for a LaunchServices-started app than for the same binary run
    /// from a shell, so "what did the real app actually get?" cannot be answered
    /// by re-running `--probe` — it has to be written down as it happens.
    private func logRefresh() {
        var lines = ["[\(Date())] 刷新完成 · 菜单栏来源 \(config.menuBarSource)"]
        for card in snapshot.cards {
            if let error = card.error {
                lines.append("\(card.name): ✗ \(error)")
                continue
            }
            let parts = card.windows.map { w -> String in
                if let remaining = w.remainingPercent { return "\(w.label) 剩余 \(Int(remaining))%" }
                return "\(w.label) \(w.value ?? "—")"
            }
            lines.append("\(card.name): " + parts.joined(separator: ", "))
        }
        if let headline = snapshot.headline(for: config.menuBar) {
            lines.append("菜单栏: \(headline.tag) \(headline.text) ← \(headline.label)"
                         + (headline.isStandIn ? " (临时代替)" : ""))
        }
        let path = Config.directory.appendingPathComponent("last-refresh.log")
        try? FileManager.default.createDirectory(at: Config.directory,
                                                 withIntermediateDirectories: true)
        try? lines.joined(separator: "\n").write(to: path, atomically: true, encoding: .utf8)
    }

    /// config.json is the only place settings live, so hand edits have to take
    /// effect without a restart. Reading it on every refresh is cheap; only a
    /// changed interval needs anything rebuilt.
    private func reloadConfig() {
        let fresh = Config.load()
        let intervalChanged = fresh.refreshMinutes != config.refreshMinutes
        config = fresh
        if intervalChanged { scheduleTimer() }
    }

    /// The one quota the menu bar reads out.
    var headline: Headline? { snapshot.headline(for: config.menuBar) }

    /// Changes made in the UI have to reach disk: `reloadConfig()` reads the
    /// file back on every refresh and would otherwise undo them.
    func setMenuBarSource(_ source: MenuBarSource) throws {
        guard config.menuBar != source else { return }
        var updated = config
        updated.menuBarSource = source.rawValue
        try updated.save()
        config = updated
    }

    var hasError: Bool { snapshot.cards.contains { $0.error != nil } }
}
