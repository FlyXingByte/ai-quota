import Foundation

/// DeepSeek exposes balance through the documented API (`/user/balance`) using an
/// API key. That is deliberately preferred over scraping platform.deepseek.com:
/// the web console authenticates with a Bearer token kept in localStorage, which
/// is neither reachable from the cookie jar nor stable across sessions.
struct DeepSeekProvider: QuotaProvider {
    let id = "deepseek"
    let name = "DeepSeek"

    /// The funded balance row — selectable as the menu bar readout.
    static let balanceKey = "deepseek.balance"

    let keychainService: String
    let keychainAccount: String

    init(keychainService: String = "DeepSeek API Key", keychainAccount: String = "codex") {
        self.keychainService = keychainService
        self.keychainAccount = keychainAccount
    }

    func fetch() async -> ProviderCard {
        var card = ProviderCard(id: id, name: name, shortName: "DS",
                                link: URL(string: "https://platform.deepseek.com/usage"))
        do {
            let key = try apiKey()
            let info = try await balance(key: key)
            apply(info, to: &card)
        } catch {
            card.error = error.localizedDescription
        }
        return card
    }

    // MARK: - Credentials

    private func apiKey() throws -> String {
        if let env = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"], !env.isEmpty {
            return env
        }
        if let key = Keychain.string(service: keychainService, account: keychainAccount),
           !key.isEmpty {
            return key
        }
        throw QuotaError.message("钥匙串里没有 \"\(keychainService)\"（账户 \(keychainAccount)）。也可以设置环境变量 DEEPSEEK_API_KEY。")
    }

    // MARK: - API

    private func balance(key: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.deepseek.com/user/balance")!)
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.message("DeepSeek: 无响应")
        }
        guard http.statusCode == 200 else {
            if http.statusCode == 401 {
                throw QuotaError.message("DeepSeek: API key 无效或已撤销 (401)")
            }
            throw QuotaError.message("DeepSeek: HTTP \(http.statusCode)")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw QuotaError.message("DeepSeek: 返回不是 JSON")
        }
        return json
    }

    private func apply(_ json: [String: Any], to card: inout ProviderCard) {
        let available = json["is_available"] as? Bool ?? false
        card.subtitle = available ? "余额可用" : "余额不足 / 不可用"

        let infos = json["balance_infos"] as? [[String: Any]] ?? []
        guard !infos.isEmpty else {
            card.error = "DeepSeek 未返回余额信息"
            return
        }
        // The API returns a row per currency; the unfunded ones are all zero and
        // would just be noise. Keep them only if nothing else has money in it.
        let funded = infos.filter { Double($0["total_balance"] as? String ?? "0") ?? 0 > 0 }
        for info in (funded.isEmpty ? Array(infos.prefix(1)) : funded) {
            let currency = info["currency"] as? String ?? ""
            let symbol = currency == "CNY" ? "¥" : (currency == "USD" ? "$" : currency + " ")
            let total = info["total_balance"] as? String ?? "0"
            let granted = info["granted_balance"] as? String ?? "0"
            let toppedUp = info["topped_up_balance"] as? String ?? "0"

            // Only the first row carries the key; with several funded
            // currencies the menu bar shows the primary one.
            card.windows.append(QuotaWindow(label: "余额（\(currency)）",
                                            key: card.windows.isEmpty
                                                ? DeepSeekProvider.balanceKey : nil,
                                            usedPercent: nil,
                                            resetsAt: nil,
                                            value: "\(symbol)\(total)"))
            if Double(granted) ?? 0 > 0 {
                card.notes.append("赠送额度：\(symbol)\(granted)")
            }
            if Double(toppedUp) ?? 0 > 0 {
                card.notes.append("充值余额：\(symbol)\(toppedUp)")
            }
        }
        if !available {
            card.notes.append("余额为零时 API 会拒绝请求")
        }
        card.notes.append("token 用量明细见网页控制台")
    }
}
