import Foundation

/// Collects everything a pipe produces, on the reader's own queue.
///
/// The obvious version — a background closure appending to a captured `var` —
/// is a data race (the compiler rejects it outright under strict concurrency),
/// and it can only guess when the last chunk landed by sleeping. A readability
/// handler plus a lock removes both problems: end-of-output is an event to wait
/// on rather than a duration to hope for.
final class PipeCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = Data()
    private var closed = false
    private let eof = DispatchSemaphore(value: 0)
    private let handle: FileHandle

    init(_ pipe: Pipe) {
        handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {  // the writer closed its end
                handle.readabilityHandler = nil
                self.markClosed()
                return
            }
            self.lock.lock()
            self.buffer.append(chunk)
            self.lock.unlock()
        }
    }

    /// Everything read so far, having waited up to `grace` for the writer to
    /// close. Returns what it has either way — a partial answer beats hanging.
    func data(waitingUpTo grace: TimeInterval = 1.0) -> Data {
        _ = eof.wait(timeout: .now() + grace)
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func text(waitingUpTo grace: TimeInterval = 1.0) -> String {
        String(data: data(waitingUpTo: grace), encoding: .utf8) ?? ""
    }

    /// Detaches the handler. Required before the pipe goes away, and safe to
    /// call more than once.
    func stop() {
        handle.readabilityHandler = nil
        markClosed()
    }

    private func markClosed() {
        lock.lock()
        let wasClosed = closed
        closed = true
        lock.unlock()
        if !wasClosed { eof.signal() }
    }
}

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

        // Both pipes are drained while the child is alive: a full pipe buffer
        // would otherwise block the child forever, timeout or not.
        let stdout = PipeCollector(out)
        let stderr = PipeCollector(err)
        defer {
            stdout.stop()
            stderr.stop()
        }

        try proc.run()

        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
            throw QuotaError.message(L("shell.timeout", URL(fileURLWithPath: path).lastPathComponent))
        }
        proc.waitUntilExit()
        return stdout.text()
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
