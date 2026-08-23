import Foundation

enum Shell {
    /// Runs a binary to completion and returns stdout. Kills it past `timeout`.
    @discardableResult
    static func run(_ path: String, _ args: [String], timeout: TimeInterval = 20) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()

        let deadline = Date().addingTimeInterval(timeout)
        var data = Data()
        let handle = out.fileHandleForReading
        // Drain while the child is alive so a big payload cannot deadlock the pipe.
        DispatchQueue.global().async {
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                data.append(chunk)
            }
        }
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
            throw QuotaError.message("\(URL(fileURLWithPath: path).lastPathComponent) 超时")
        }
        proc.waitUntilExit()
        Thread.sleep(forTimeInterval: 0.05)  // let the drain thread flush
        if data.isEmpty {
            data = (try? handle.readToEnd()) ?? Data()
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// First existing path for a CLI, searching the usual non-login-shell blind spots.
    static func locate(_ name: String, extraPaths: [String] = []) -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = extraPaths + [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
            "\(home)/.npm-global/bin/\(name)",
            "/usr/bin/\(name)",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
