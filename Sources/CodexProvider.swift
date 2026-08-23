import Foundation

/// Codex quota comes from the CLI's own app-server over JSON-RPC on stdio —
/// no tokens or cookies pass through this app.
///   initialize -> account/rateLimits/read
struct CodexProvider: QuotaProvider {
    let id = "codex"
    let name = "Codex"

    /// The account-wide weekly limit — the number that actually governs a week
    /// of work, and the menu bar's default readout.
    static let weeklyKey = "codex.weekly"

    func fetch() async -> ProviderCard {
        var card = ProviderCard(id: id, name: name, shortName: "Cx",
                                link: URL(string: "https://chatgpt.com/codex/settings/usage"))
        guard let bin = Shell.locate("codex") else {
            card.error = L("codex.not_installed")
            return card
        }
        do {
            let result = try callRateLimits(bin: bin)
            apply(result, to: &card)
        } catch {
            card.error = error.localizedDescription
        }
        return card
    }

    // MARK: - JSON-RPC over stdio

    private func callRateLimits(bin: String) throws -> [String: Any] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: bin)
        proc.arguments = ["app-server"]
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        let reader = JSONLineReader(stdout)
        // Drained rather than ignored: a full stderr buffer would block the
        // child, and its tail is the only clue when the server says nothing.
        let diagnostics = PipeCollector(stderr)
        try proc.run()
        defer {
            reader.stop()
            diagnostics.stop()
            // Closing stdin is how a stdio JSON-RPC server is asked to leave;
            // terminate() is the follow-up for one that will not.
            try? stdin.fileHandleForWriting.close()
            if proc.isRunning { proc.terminate() }
        }

        func send(_ obj: [String: Any]) throws {
            var line = try JSONSerialization.data(withJSONObject: obj)
            line.append(0x0A)
            stdin.fileHandleForWriting.write(line)
        }

        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["clientInfo": ["name": "AIQuota", "title": "AI Quota",
                                            "version": AppInfo.version]]])
        _ = try awaitResponse(id: 1, from: reader, diagnostics: diagnostics, timeout: 30)

        try send(["jsonrpc": "2.0", "method": "initialized", "params": NSNull()])
        try send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read",
                  "params": NSNull()])
        let response = try awaitResponse(id: 2, from: reader,
                                         diagnostics: diagnostics, timeout: 45)

        if let err = response["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "\(err)"
            throw QuotaError.message("Codex: \(msg)")
        }
        guard let result = response["result"] as? [String: Any] else {
            throw QuotaError.message(L("codex.unrecognized_response"))
        }
        return result
    }

    /// Waits for one numbered response, ignoring the server's notifications.
    ///
    /// The deadline here is real. The previous version polled
    /// `FileHandle.availableData`, which blocks until bytes arrive — so a server
    /// that started and then went quiet without exiting was never timed out at
    /// all, and since a refresh holds its in-progress flag until it returns,
    /// that one stall silently killed every later refresh too.
    private func awaitResponse(id wanted: Int, from reader: JSONLineReader,
                               diagnostics: PipeCollector,
                               timeout: TimeInterval) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let message = reader.take(id: wanted) { return message }
            if reader.isClosed {
                throw QuotaError.message(L("codex.server_exited")
                                         + Self.hint(from: diagnostics))
            }
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw QuotaError.message(L("codex.server_silent", Int(timeout))
                                         + Self.hint(from: diagnostics))
            }
            reader.waitForMessage(upTo: remaining)
        }
    }

    /// The last line the server printed to stderr, when there is one.
    private static func hint(from diagnostics: PipeCollector) -> String {
        let tail = diagnostics.text(waitingUpTo: 0.1)
            .split(separator: "\n")
            .last?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !tail.isEmpty else { return "" }
        return "：\(tail.prefix(160))"
    }

    // MARK: - Shaping

    private func apply(_ result: [String: Any], to card: inout ProviderCard) {
        let byLimit = result["rateLimitsByLimitId"] as? [String: Any] ?? [:]
        let fallback = result["rateLimits"] as? [String: Any]

        // Prefer the per-limit breakdown; it names each model bucket.
        var buckets: [(String, [String: Any])] = byLimit.compactMap { key, value in
            guard let dict = value as? [String: Any] else { return nil }
            return (key, dict)
        }
        if buckets.isEmpty, let fallback { buckets = [("codex", fallback)] }
        // "codex" is the account-wide bucket; show it first.
        buckets.sort { a, b in
            if a.0 == "codex" { return true }
            if b.0 == "codex" { return false }
            return a.0 < b.0
        }

        for (limitID, snapshot) in buckets {
            // Whether this is the unnamed account-wide bucket — the only one
            // whose name the row label leaves off.
            let isAccountWide = limitID == "codex" && snapshot["limitName"] == nil
            let display = (snapshot["limitName"] as? String)
                ?? (limitID == "codex" ? L("codex.account_limit") : limitID)
            if card.subtitle == nil, let plan = snapshot["planType"] as? String {
                card.subtitle = L("plan.subtitle", plan.uppercased())
            }
            for slot in ["primary", "secondary"] {
                guard let window = snapshot[slot] as? [String: Any],
                      let used = window["usedPercent"] as? NSNumber else { continue }
                let mins = (window["windowDurationMins"] as? NSNumber)?.doubleValue
                var label = windowLabel(minutes: mins)
                if buckets.count > 1 || !isAccountWide { label = "\(display) · \(label)" }
                var resets: Date?
                if let ts = (window["resetsAt"] as? NSNumber)?.doubleValue, ts > 0 {
                    resets = Date(timeIntervalSince1970: ts)
                }
                // The account-wide weekly window is the one the menu bar pins to,
                // so tag it rather than leaving the UI to match on label text.
                let key = (limitID == "codex" && mins == 10080)
                    ? CodexProvider.weeklyKey : nil
                card.windows.append(QuotaWindow(label: label,
                                                key: key,
                                                usedPercent: used.doubleValue,
                                                resetsAt: resets))
            }
            if let credits = snapshot["credits"] as? [String: Any] {
                if credits["unlimited"] as? Bool == true {
                    card.notes.append(ProviderNote(text: L("codex.credits_unlimited")))
                } else if let balance = credits["balance"] as? String,
                          Double(balance) ?? 0 > 0 {
                    card.notes.append(ProviderNote(text: L("codex.credits_balance", balance)))
                }
            }
        }

        if let resetCredits = result["rateLimitResetCredits"] as? [String: Any],
           let count = (resetCredits["availableCount"] as? NSNumber)?.intValue, count > 0 {
            card.notes.append(ProviderNote(text: L("codex.reset_credits", count)))
        }
        if card.windows.isEmpty {
            card.error = L("codex.no_windows")
        }
    }

    private func windowLabel(minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return L("window.current") }
        switch minutes {
        case ..<60: return L("window.minutes", Int(minutes))
        case ..<1440: return L("window.hours", Int(minutes / 60))
        case 10080: return L("window.weekly")
        case 1440: return L("window.daily")
        default: return L("window.days", Int(minutes / 1440))
        }
    }
}

/// Newline-delimited JSON off a pipe, delivered as events rather than by polling.
///
/// Parsing happens on the pipe's own readability queue, so a waiter only ever
/// blocks on a semaphore with a deadline — never on a read that may never
/// return. Notifications (messages with no numeric `id`) are dropped as they
/// arrive so a long-lived session cannot accumulate them.
final class JSONLineReader: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var responses: [[String: Any]] = []
    private var closed = false
    private let arrived = DispatchSemaphore(value: 0)
    private let handle: FileHandle

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.markClosed()
                return
            }
            self.ingest(chunk)
        }
    }

    /// True once the server closed its end — no further response can arrive.
    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    /// Removes and returns the response carrying `id`, if it has arrived.
    func take(id wanted: Int) -> [String: Any]? {
        lock.lock()
        defer { lock.unlock() }
        guard let index = responses.firstIndex(where: { ($0["id"] as? Int) == wanted }) else {
            return nil
        }
        return responses.remove(at: index)
    }

    /// Blocks until something new arrives, the pipe closes, or `seconds` elapse.
    func waitForMessage(upTo seconds: TimeInterval) {
        _ = arrived.wait(timeout: .now() + seconds)
    }

    func stop() {
        handle.readabilityHandler = nil
        markClosed()
    }

    private func ingest(_ chunk: Data) {
        lock.lock()
        buffer.append(chunk)
        var complete: [Data] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer = buffer[buffer.index(after: newline)...]
            if !line.isEmpty { complete.append(Data(line)) }
        }
        lock.unlock()

        var parsed: [[String: Any]] = []
        for line in complete {
            guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  message["id"] is Int else { continue }  // notifications are noise here
            parsed.append(message)
        }
        guard !parsed.isEmpty else { return }

        lock.lock()
        responses.append(contentsOf: parsed)
        lock.unlock()
        arrived.signal()
    }

    private func markClosed() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        if !wasClosed { arrived.signal() }
    }
}
