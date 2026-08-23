import Foundation

/// Codex quota comes from the CLI's own app-server over JSON-RPC on stdio —
/// no tokens or cookies pass through this app.
///   initialize -> account/rateLimits/read
struct CodexProvider: QuotaProvider {
    let id = "codex"
    let name = "Codex"

    func fetch() async -> ProviderCard {
        var card = ProviderCard(id: id, name: name,
                                link: URL(string: "https://chatgpt.com/codex/settings/usage"))
        guard let bin = Shell.locate("codex") else {
            card.error = "找不到 codex 命令（试过 ~/.local/bin、homebrew）"
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
        try proc.run()
        defer { if proc.isRunning { proc.terminate() } }

        func send(_ obj: [String: Any]) throws {
            var line = try JSONSerialization.data(withJSONObject: obj)
            line.append(0x0A)
            stdin.fileHandleForWriting.write(line)
        }

        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["clientInfo": ["name": "AIQuota", "title": "AI Quota",
                                            "version": AppInfo.version]]])
        _ = try awaitResponse(id: 1, from: stdout, proc: proc, timeout: 30)

        try send(["jsonrpc": "2.0", "method": "initialized", "params": NSNull()])
        try send(["jsonrpc": "2.0", "id": 2, "method": "account/rateLimits/read",
                  "params": NSNull()])
        let response = try awaitResponse(id: 2, from: stdout, proc: proc, timeout: 45)

        if let err = response["error"] as? [String: Any] {
            let msg = err["message"] as? String ?? "\(err)"
            throw QuotaError.message("Codex: \(msg)")
        }
        guard let result = response["result"] as? [String: Any] else {
            throw QuotaError.message("Codex 返回了无法识别的响应")
        }
        return result
    }

    /// Reads newline-delimited JSON, skipping the server's unsolicited notifications.
    private func awaitResponse(id wanted: Int, from pipe: Pipe, proc: Process,
                               timeout: TimeInterval) throws -> [String: Any] {
        let handle = pipe.fileHandleForReading
        var buffer = Data()
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            let chunk = handle.availableData
            if chunk.isEmpty {
                if !proc.isRunning { break }
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[buffer.startIndex..<nl]
                buffer = buffer[buffer.index(after: nl)...]
                guard !lineData.isEmpty,
                      let msg = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any]
                else { continue }
                if let mid = msg["id"] as? Int, mid == wanted { return msg }
            }
        }
        throw QuotaError.message("Codex app-server 无响应（超时）")
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
            let display = (snapshot["limitName"] as? String)
                ?? (limitID == "codex" ? "账号额度" : limitID)
            if card.subtitle == nil, let plan = snapshot["planType"] as? String {
                card.subtitle = "\(plan.uppercased()) 计划"
            }
            for slot in ["primary", "secondary"] {
                guard let window = snapshot[slot] as? [String: Any],
                      let used = window["usedPercent"] as? NSNumber else { continue }
                let mins = (window["windowDurationMins"] as? NSNumber)?.doubleValue
                var label = windowLabel(minutes: mins)
                if buckets.count > 1 || display != "账号额度" { label = "\(display) · \(label)" }
                var resets: Date?
                if let ts = (window["resetsAt"] as? NSNumber)?.doubleValue, ts > 0 {
                    resets = Date(timeIntervalSince1970: ts)
                }
                card.windows.append(QuotaWindow(label: label,
                                                usedPercent: used.doubleValue,
                                                resetsAt: resets))
            }
            if let credits = snapshot["credits"] as? [String: Any] {
                if credits["unlimited"] as? Bool == true {
                    card.notes.append("额度信用：无限")
                } else if let balance = credits["balance"] as? String,
                          Double(balance) ?? 0 > 0 {
                    card.notes.append("额度信用余额：\(balance)")
                }
            }
        }

        if let resetCredits = result["rateLimitResetCredits"] as? [String: Any],
           let count = (resetCredits["availableCount"] as? NSNumber)?.intValue, count > 0 {
            card.notes.append("可用重置券：\(count) 张")
        }
        if card.windows.isEmpty {
            card.error = "Codex 未返回任何额度窗口（可能未登录，试试 codex login）"
        }
    }

    private func windowLabel(minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "当前窗口" }
        switch minutes {
        case ..<60: return "\(Int(minutes)) 分钟"
        case ..<1440: return "\(Int(minutes / 60)) 小时"
        case 10080: return "每周"
        case 1440: return "每天"
        default: return "\(Int(minutes / 1440)) 天"
        }
    }
}
