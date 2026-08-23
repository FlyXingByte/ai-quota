import AppKit
import Combine
import Foundation
import Network

/// Owns the snapshot and the refresh schedule. Providers run concurrently so one
/// slow source never holds up the rest.
@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var snapshot = Snapshot()
    @Published private(set) var config: Config

    private var timer: Timer?
    private var started = false
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var wakeObserver: NSObjectProtocol?
    private var networkMonitor: NWPathMonitor?
    private var wasOffline = false

    init(config: Config = .load()) {
        self.config = config
    }

    func start() {
        guard config.setupCompleted, !started else { return }
        started = true
        Task { await refresh() }
        scheduleTimer()
        observeSystemEvents()
    }

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, config.refreshMinutes) * 60)
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                // Each scheduled round starts with a full retry budget.
                self?.retryAttempt = 0
                await self?.refresh()
            }
        }
        // A quota readout is not worth waking the CPU on the dot; letting the
        // system coalesce this with other timers is the usual courtesy for a
        // menu bar app that lives for weeks at a time.
        timer.tolerance = interval * 0.1
        self.timer = timer
    }

    /// A refresh is skipped while the machine sleeps, and one attempted with no
    /// network only produces errors. Both leave the readout older than it looks.
    private func observeSystemEvents() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfOlderThan(120) }
        }

        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let satisfied = path.status == .satisfied
                defer { self.wasOffline = !satisfied }
                // Only on the transition back: the handler also fires for
                // interface changes that were never an outage.
                guard satisfied, self.wasOffline else { return }
                self.refreshIfOlderThan(30)
            }
        }
        monitor.start(queue: DispatchQueue(label: "\(AppInfo.bundleID).network"))
        networkMonitor = monitor
    }

    /// Refreshes only if what is on screen has aged past `seconds`.
    ///
    /// `updatedAt` records the last *attempt*, so a run of failures keeps it
    /// looking recent. Anything currently in error is therefore always worth
    /// another try at these moments — waking and regaining a network are
    /// exactly the events that fix it.
    private func refreshIfOlderThan(_ seconds: TimeInterval) {
        guard config.setupCompleted, started else { return }
        if !hasError, let updatedAt = snapshot.updatedAt,
           Date().timeIntervalSince(updatedAt) < seconds { return }
        retryAttempt = 0
        Task { await refresh() }
    }

    /// Upper bound on a single provider, past which its card is abandoned.
    /// Generous on purpose: Codex's own JSON-RPC budget is 30 + 45 seconds, so
    /// in a normal failure its own message wins and this stays a backstop.
    private static let providerTimeout: TimeInterval = 90

    func refresh() async {
        guard !snapshot.refreshing else { return }
        retryTask?.cancel()
        retryTask = nil
        reloadConfig()
        snapshot.refreshing = true
        // Cleared on every exit path: while this flag is up, every other
        // refresh — the timer's and the user's — returns at the guard above.
        defer {
            snapshot.refreshing = false
            logRefresh()
        }
        let providers = config.providers

        let cards = await withTaskGroup(of: (Int, ProviderCard).self) { group in
            for (index, provider) in providers.enumerated() {
                group.addTask { (index, await Self.fetch(provider,
                                                         timeout: Self.providerTimeout)) }
            }
            var collected: [(Int, ProviderCard)] = []
            for await result in group { collected.append(result) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }

        snapshot.cards = Self.merge(cards, over: snapshot.cards)
        snapshot.updatedAt = Date()
        scheduleRetryIfNeeded()
    }

    /// Keeps the last good reading of any source that just failed.
    ///
    /// A provider reports failure by returning a card with nothing but an
    /// error, which used to replace the numbers outright: one flaky minute and
    /// the panel went blank and the menu bar fell back to "!" — for the whole
    /// ten-minute interval, over a blip that says nothing about the quota. The
    /// error is still shown; it is now shown *next to* the last numbers, marked
    /// as what they are.
    private nonisolated static func merge(_ fresh: [ProviderCard],
                                          over previous: [ProviderCard]) -> [ProviderCard] {
        let now = Date()
        return fresh.map { card in
            guard card.error != nil, card.windows.isEmpty else {
                var card = card
                card.readAt = now
                return card
            }
            guard let old = previous.first(where: { $0.id == card.id }),
                  !old.windows.isEmpty else { return card }

            var kept = old
            kept.error = card.error
            kept.isStale = true
            kept.readAt = old.readAt
            return kept
        }
    }

    /// One or two quick retries after a failure, instead of leaving a stale
    /// readout up for the whole refresh interval. The budget is per scheduled
    /// round: it resets on the timer, on wake, and on a network recovery.
    private static let retryDelays: [TimeInterval] = [60, 180]

    private func scheduleRetryIfNeeded() {
        guard hasError, retryAttempt < Self.retryDelays.count else {
            if !hasError { retryAttempt = 0 }
            return
        }
        let delay = Self.retryDelays[retryAttempt]
        retryAttempt += 1
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.retryTask = nil }
            await self?.refresh()
        }
    }

    /// `provider.fetch()`, but never for longer than `timeout`.
    ///
    /// The work runs in a detached task rather than as a child of a task group:
    /// a group does not return until every child has finished, so racing a
    /// sleeper against a provider stuck in blocking system code would still hold
    /// the refresh down. Abandoning the task is the point — whatever it is
    /// waiting on, the store keeps moving.
    private static func fetch(_ provider: QuotaProvider,
                              timeout: TimeInterval) async -> ProviderCard {
        await withCheckedContinuation { continuation in
            let box = FirstResult(continuation)
            let deadline = Task.detached {
                do {
                    try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                } catch {
                    return  // cancelled: the provider answered in time
                }
                var card = ProviderCard(id: provider.id, name: provider.name)
                card.error = L("store.provider_timeout", provider.name, Int(timeout))
                box.settle(card)
            }
            Task.detached {
                box.settle(await provider.fetch())
                deadline.cancel()
            }
        }
    }

    /// Records the result of each refresh. Keychain and cookie access behave
    /// differently for a LaunchServices-started app than for the same binary run
    /// from a shell, so "what did the real app actually get?" cannot be answered
    /// by re-running `--probe` — it has to be written down as it happens.
    private func logRefresh() {
        var lines = ["[\(Date())] refresh complete · menu bar source \(config.menuBarSource)"]
        for card in snapshot.cards {
            if let error = card.error, card.windows.isEmpty {
                lines.append("\(card.name): ✗ \(error)")
                continue
            }
            let parts = card.windows.map { w -> String in
                if let remaining = w.remainingPercent { return "\(w.label) \(Int(remaining))% left" }
                return "\(w.label) \(w.value ?? "—")"
            }
            let age = card.isStale
                ? "  ⚠︎ kept previous reading (\(Fmt.since(card.readAt) ?? "unknown age")): "
                  + "\(card.error ?? "")"
                : ""
            lines.append("\(card.name): " + parts.joined(separator: ", ") + age)
        }
        if let headline = snapshot.headline(for: config.menuBar) {
            lines.append("menu bar: \(headline.tag) \(headline.text) ← \(headline.label)"
                         + (headline.isStandIn ? " (stand-in)" : ""))
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

    /// Applies first-run or later source settings. DeepSeek credentials are
    /// written directly to Keychain and are never represented in Config.
    func applySetup(showCodex: Bool,
                    showClaude: Bool,
                    showOpenCode: Bool,
                    workspaceID: String,
                    showDeepSeek: Bool,
                    deepSeekKey: String) throws {
        if showOpenCode && workspaceID.isEmpty {
            throw QuotaError.message(L("setup.workspace_required"))
        }

        var updated = config
        updated.showCodex = showCodex
        updated.showClaude = showClaude
        updated.showOpenCode = showOpenCode
        updated.opencodeWorkspaceID = workspaceID
        updated.showDeepSeek = showDeepSeek
        updated.setupCompleted = true

        let trimmedKey = deepSeekKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedKey.isEmpty {
            try Keychain.store(trimmedKey,
                               service: updated.deepseekKeychainService,
                               account: updated.deepseekKeychainAccount)
        }

        // Switching a source off must not leave the menu bar pinned to it:
        // that reads out a silent stand-in forever with nothing saying why.
        if !updated.menuBar.isAvailable(in: updated) {
            updated.menuBarSource = (MenuBarSource.allCases.first { $0.isAvailable(in: updated) }
                                     ?? .tightest).rawValue
        }

        try updated.save()
        config = updated
        if started {
            scheduleTimer()
            Task { await refresh() }
        } else {
            start()
        }
    }

    var hasError: Bool { snapshot.cards.contains { $0.error != nil } }
}

/// Resumes a continuation exactly once, whichever racer gets there first.
private final class FirstResult: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<ProviderCard, Never>?

    init(_ continuation: CheckedContinuation<ProviderCard, Never>) {
        self.continuation = continuation
    }

    func settle(_ card: ProviderCard) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: card)
    }
}
