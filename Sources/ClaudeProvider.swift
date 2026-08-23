import Foundation

/// Claude subscription limits, read the same way Claude Code reads them:
/// the OAuth token from the login keychain item, then
/// `GET https://api.anthropic.com/api/oauth/usage`.
///
/// The token is used strictly read-only. Claude Code owns its refresh cycle —
/// refreshing here would rotate the refresh token underneath it and could log
/// the CLI out, so an expired token is reported rather than renewed.
struct ClaudeProvider: QuotaProvider {
    let id = "claude"
    let name = "Claude"

    /// The weekly bucket — selectable as the menu bar readout.
    static let weeklyKey = "claude.weekly"

    static let keychainService = "Claude Code-credentials"

    func fetch() async -> ProviderCard {
        var card = ProviderCard(id: id, name: name, shortName: "Cl",
                                link: URL(string: "https://claude.ai/settings/usage"))
        do {
            let credentials = try oauth()
            card.subtitle = credentials.plan.map { L("plan.subtitle", $0.uppercased()) }
            let payload = try await usage(token: credentials.token)
            apply(payload, to: &card)
        } catch {
            card.error = error.localizedDescription
        }
        return card
    }

    // MARK: - Credentials

    private struct OAuth {
        var token: String
        var plan: String?
    }

    /// Cached so a refresh every few minutes does not re-hit the keychain — and
    /// so a user who granted access only "once" is not re-prompted on a timer.
    /// Dropped before the token expires, which is when it has to be re-read.
    private static let cacheGate = NSLock()
    nonisolated(unsafe) private static var cached: (oauth: OAuth, until: Date)?

    private func oauth() throws -> OAuth {
        ClaudeProvider.cacheGate.lock()
        if let cached = ClaudeProvider.cached, cached.until > Date() {
            ClaudeProvider.cacheGate.unlock()
            return cached.oauth
        }
        ClaudeProvider.cacheGate.unlock()

        let fresh = try readKeychain()
        ClaudeProvider.cacheGate.lock()
        ClaudeProvider.cached = (fresh.oauth, fresh.expiry)
        ClaudeProvider.cacheGate.unlock()
        return fresh.oauth
    }

    private func readKeychain() throws -> (oauth: OAuth, expiry: Date) {
        let result = Keychain.read(service: ClaudeProvider.keychainService)
        guard result.status == errSecSuccess, let data = result.data else {
            var message = Keychain.explain(result.status, item: ClaudeProvider.keychainService)
            if result.status == errSecItemNotFound { message += L("claude.login_hint") }
            throw QuotaError.message(message)
        }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            throw QuotaError.message(L("claude.credentials_unreadable"))
        }

        // expiresAt is milliseconds since epoch.
        var expiry = Date().addingTimeInterval(30 * 60)  // no expiry given: re-read occasionally
        if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue, expiresAt > 0 {
            let tokenExpiry = Date(timeIntervalSince1970: expiresAt / 1000)
            if tokenExpiry < Date() {
                throw QuotaError.message(
                    L("claude.token_expired", Fmt.stamp(tokenExpiry)))
            }
            // Stop trusting the cache a minute early so a refresh never rides an
            // token that expires mid-request.
            expiry = min(expiry, tokenExpiry.addingTimeInterval(-60))
        }
        let credentials = OAuth(token: token, plan: oauth["subscriptionType"] as? String)
        return (credentials, expiry)
    }

    // MARK: - API

    private func usage(token: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        // A quota is the one thing that must never come from a cache.
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.message(L("claude.no_response"))
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw QuotaError.message(L("claude.unauthorized"))
            }
            throw QuotaError.message("Claude: HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.message(L("claude.not_json"))
        }
        return json
    }

    /// Raw response, for `--dump claude`.
    func rawUsage() async throws -> [String: Any] {
        try await usage(token: oauth().token)
    }

    // MARK: - Shaping

    /// `label` is a localization key, resolved when the card is built.
    private static let buckets: [(field: String, label: String, key: String?)] = [
        ("five_hour", "window.five_hour", nil),
        ("seven_day", "window.weekly", ClaudeProvider.weeklyKey),
        ("seven_day_opus", "window.weekly_opus", nil),
        ("seven_day_sonnet", "window.weekly_sonnet", nil),
    ]

    private func apply(_ json: [String: Any], to card: inout ProviderCard) {
        for bucket in ClaudeProvider.buckets {
            guard let raw = json[bucket.field] as? [String: Any] else { continue }
            guard let used = utilizationPercent(raw) else { continue }
            card.windows.append(QuotaWindow(label: L(bucket.label),
                                            key: bucket.key,
                                            usedPercent: used,
                                            resetsAt: resetDate(raw)))
        }

        applySpend(json, to: &card)
        if card.windows.isEmpty {
            card.error = L("claude.no_windows", json.keys.sorted().joined(separator: ", "))
        }
    }

    /// `utilization` is already a 0–100 percentage — verified against a live
    /// response. Do not "helpfully" rescale small values: a genuine 1% would
    /// become 100%.
    private func utilizationPercent(_ raw: [String: Any]) -> Double? {
        for field in ["utilization", "percent"] {
            if let number = raw[field] as? NSNumber { return number.doubleValue }
        }
        return nil
    }

    /// Pay-as-you-go credits that cover overflow past the plan limits. Reported
    /// as a note, not a bar: when they are switched off the percentage would
    /// read like a live quota it is not.
    private func applySpend(_ json: [String: Any], to card: inout ProviderCard) {
        guard let spend = json["spend"] as? [String: Any] else { return }
        guard let used = money(spend["used"]), let limit = money(spend["limit"]) else { return }

        var note = L("claude.extra_usage", used, limit)
        if let percent = (spend["percent"] as? NSNumber)?.intValue {
            note += L("claude.extra_usage_percent", percent)
        }
        var needsAttention = false
        if spend["enabled"] as? Bool != true {
            let reason = spend["disabled_reason"] as? String
            note += L(reason == "out_of_credits" ? "claude.extra_usage_out" : "claude.extra_usage_off")
            needsAttention = true
        }
        card.notes.append(ProviderNote(text: note, needsAttention: needsAttention))
    }

    /// `{amount_minor: 8555, currency: "EUR", exponent: 2}` -> "€85.55".
    private func money(_ raw: Any?) -> String? {
        guard let raw = raw as? [String: Any],
              let minor = (raw["amount_minor"] as? NSNumber)?.doubleValue else { return nil }
        let exponent = (raw["exponent"] as? NSNumber)?.intValue ?? 2
        let currency = raw["currency"] as? String ?? ""
        let symbol = ["EUR": "€", "USD": "$", "GBP": "£", "CNY": "¥"][currency]
            ?? (currency.isEmpty ? "" : currency + " ")
        let value = minor / pow(10, Double(exponent))
        return symbol + String(format: "%.\(exponent)f", value)
    }

    private func resetDate(_ raw: [String: Any]) -> Date? {
        for field in ["resets_at", "reset_at", "resetsAt"] {
            if let seconds = (raw[field] as? NSNumber)?.doubleValue, seconds > 0 {
                // Seconds or milliseconds, depending on the field's vintage.
                return Date(timeIntervalSince1970: seconds > 1e11 ? seconds / 1000 : seconds)
            }
            if let text = raw[field] as? String, !text.isEmpty {
                let iso = ISO8601DateFormatter()
                iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = iso.date(from: text) { return date }
                iso.formatOptions = [.withInternetDateTime]
                if let date = iso.date(from: text) { return date }
            }
        }
        return nil
    }
}
