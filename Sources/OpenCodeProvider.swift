import Foundation

/// opencode has no public quota API (see anomalyco/opencode#10448), so this
/// re-uses the Chrome session and reads the numbers out of the server-rendered
/// page. The console is SolidStart: `queryLiteSubscription` resolves on the
/// server and its result is serialized into the HTML for hydration, which is
/// what we parse — no scraping of rendered pixels, no server-function IDs that
/// change on every deploy.
struct OpenCodeProvider: QuotaProvider {
    let id = "opencode"
    let name = "OpenCode"

    /// The weekly Go/Lite window — selectable as the menu bar readout.
    static let weeklyKey = "opencode.weekly"

    let workspaceID: String

    var goURL: URL { URL(string: "https://opencode.ai/workspace/\(workspaceID)/go")! }
    var billingURL: URL { URL(string: "https://opencode.ai/workspace/\(workspaceID)/billing")! }

    func fetch() async -> ProviderCard {
        var card = ProviderCard(id: id, name: name, shortName: "OC", link: goURL)
        do {
            let cookie = try ChromeCookies.header(matching: "%opencode.ai")
            let html = try await page(goURL, cookie: cookie)
            try applyGo(html, to: &card)

            // Balance lives on a different tab of the same console.
            if let billingHTML = try? await page(billingURL, cookie: cookie) {
                applyBilling(billingHTML, to: &card)
            }
        } catch {
            card.error = error.localizedDescription
        }
        return card
    }

    // MARK: - Fetch

    private func page(_ url: URL, cookie: String) async throws -> String {
        var req = URLRequest(url: url)
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                     + "(KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36",
                     forHTTPHeaderField: "User-Agent")
        req.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 25

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw QuotaError.message("opencode: 无响应")
        }
        if (300..<400).contains(http.statusCode) {
            let dest = http.value(forHTTPHeaderField: "Location") ?? ""
            if dest.contains("/auth") {
                throw QuotaError.message("opencode 会话已过期，请在 Chrome 里重新登录 opencode.ai")
            }
            throw QuotaError.message("opencode: 意外跳转到 \(dest)")
        }
        guard http.statusCode == 200 else {
            throw QuotaError.message("opencode: HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Redirects must be visible, not followed: a 302 to /auth is how we detect
    /// an expired session.
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            completionHandler(nil)
        }
    }

    // MARK: - Parse

    private func applyGo(_ html: String, to card: inout ProviderCard) throws {
        let slots: [(key: String, label: String, tag: String?)] = [
            ("rollingUsage", "滚动窗口", nil),
            ("weeklyUsage", "每周", OpenCodeProvider.weeklyKey),
            ("monthlyUsage", "每月", nil),
        ]
        var found = 0
        for slot in slots {
            guard let block = Payload.window(after: slot.key, in: html) else { continue }
            found += 1
            var resets: Date?
            if let secs = block.resetInSec, secs > 0 {
                resets = Date().addingTimeInterval(TimeInterval(secs))
            }
            var label = slot.label
            if let status = block.status, status != "ok" {
                label += status == "limited" ? "（已限流）" : "（\(status)）"
            }
            card.windows.append(QuotaWindow(label: label,
                                            key: slot.tag,
                                            usedPercent: block.usagePercent.map(Double.init),
                                            resetsAt: resets))
        }

        if found == 0 {
            if html.contains("workspace.lite.loading") || html.contains("data-page=\"workspace-[id]\"") {
                throw QuotaError.message("opencode: 该工作区没有 Go/Lite 订阅额度数据")
            }
            throw QuotaError.message("opencode: 页面结构变了，解析不到额度（可用 --dump 排查）")
        }
        if card.subtitle == nil { card.subtitle = "opencode Go" }
    }

    private func applyBilling(_ html: String, to card: inout ProviderCard) {
        // Console money values are micro-cents integers.
        if let raw = Payload.number(forKey: "balance", in: html) {
            card.windows.append(QuotaWindow(label: "Zen 余额",
                                            usedPercent: nil,
                                            resetsAt: nil,
                                            value: Fmt.microCents(Double(raw))))
        }
        if let limit = Payload.number(forKey: "monthlyLimit", in: html), limit > 0 {
            card.notes.append("月度上限：\(Fmt.microCents(Double(limit)))")
        }
    }
}

/// Pulls values out of the hydration payload. SolidStart serializes with seroval,
/// which emits JS object literals (unquoted keys), so this tolerates both
/// `usagePercent:42` and `"usagePercent":42`.
enum Payload {
    struct Window {
        var status: String?
        var resetInSec: Int?
        var usagePercent: Int?
    }

    /// Scans a bounded region after `anchor` for the three fields of a usage window.
    ///
    /// seroval writes either `weeklyUsage:$R[36]={status:…}` (inline) or
    /// `weeklyUsage:$R[36]` (a back-reference to an object defined earlier).
    /// The span is deliberately tight so a back-reference yields nothing rather
    /// than silently picking up the *next* window's numbers.
    static func window(after anchor: String, in html: String, span: Int = 200) -> Window? {
        // The key can appear more than once (the hydration payload is preceded by
        // other references to it), so try every occurrence and keep the first that
        // actually carries numbers.
        var searchStart = html.startIndex
        while let start = html.range(of: anchor, range: searchStart..<html.endIndex) {
            searchStart = start.upperBound
            let to = html.index(start.upperBound, offsetBy: span, limitedBy: html.endIndex)
                ?? html.endIndex
            var region = String(html[start.upperBound..<to])

            // Back-reference: `:$R[36],` or `:$R[36]}` with no `=` — resolve it.
            if let ref = firstMatch("^\\s*:\\s*\\$R\\[(\\d+)\\](?!\\s*=)", in: region),
               let resolved = definition(ofRef: ref, in: html) {
                region = resolved
            }

            var out = Window()
            out.usagePercent = number(forKey: "usagePercent", in: region).map(Int.init)
            out.resetInSec = number(forKey: "resetInSec", in: region).map(Int.init)
            out.status = string(forKey: "status", in: region)
            if out.usagePercent != nil { return out }
        }
        return nil
    }

    static func number(forKey key: String, in text: String) -> Int64? {
        let pattern = "[\"']?\\b\(NSRegularExpression.escapedPattern(for: key))\\b[\"']?\\s*:\\s*(-?\\d+)"
        return firstMatch(pattern, in: text).flatMap(Int64.init)
    }

    static func string(forKey key: String, in text: String) -> String? {
        let pattern = "[\"']?\\b\(NSRegularExpression.escapedPattern(for: key))\\b[\"']?\\s*:\\s*[\"']([^\"']*)[\"']"
        return firstMatch(pattern, in: text)
    }

    /// Finds `$R[n]={…}` and returns the object body.
    private static func definition(ofRef ref: String, in html: String) -> String? {
        let anchor = "$R[\(ref)]="
        guard let range = html.range(of: anchor) else { return nil }
        let from = range.upperBound
        let to = html.index(from, offsetBy: 200, limitedBy: html.endIndex) ?? html.endIndex
        return String(html[from..<to])
    }

    static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)),
              m.numberOfRanges > 1 else { return nil }
        return ns.substring(with: m.range(at: 1))
    }
}
