import Combine
import Foundation

/// Owns the snapshot and the refresh schedule. Providers run concurrently so one
/// slow source never holds up the rest.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published var config: Config

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
    }

    /// The single number worth putting in the menu bar: the smallest amount of
    /// quota left across everything that reports a percentage.
    var headline: (remaining: Double, provider: String)? {
        var lowest: (Double, String)?
        for card in snapshot.cards {
            guard let tightest = card.tightest,
                  let remaining = tightest.remainingPercent else { continue }
            if lowest == nil || remaining < lowest!.0 { lowest = (remaining, card.name) }
        }
        return lowest.map { (remaining: $0.0, provider: $0.1) }
    }

    var hasError: Bool { snapshot.cards.contains { $0.error != nil } }
}
