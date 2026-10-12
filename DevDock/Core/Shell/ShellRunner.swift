import Foundation

nonisolated struct ShellResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

nonisolated enum ShellError: LocalizedError {
    case launchFailed(String)
    case timedOut(Duration)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason): "Could not launch process: \(reason)"
        case .timedOut(let timeout): "Process timed out after \(timeout)"
        }
    }
}

/// Runs external commands off the main actor.
///
/// Meant for short-lived commands (lsof, git, docker ps, …). Long-running
/// processes such as dev servers need a different runner (planned for M5).
nonisolated enum ShellRunner {
    /// Runs an executable with the user's login-shell PATH.
    static func run(
        _ executable: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        timeout: Duration = .seconds(10)
    ) async throws -> ShellResult {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = await LoginEnvironment.shared.path()
        return try await launch(
            executable: executable,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            timeout: timeout
        )
    }

    /// Runs a command line through zsh, e.g. `shell("pnpm -v")`.
    static func shell(
        _ command: String,
        currentDirectory: URL? = nil,
        timeout: Duration = .seconds(10)
    ) async throws -> ShellResult {
        try await run("/bin/zsh", arguments: ["-c", command], currentDirectory: currentDirectory, timeout: timeout)
    }

    static func launch(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL?,
        timeout: Duration
    ) async throws -> ShellResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }

        let stdout = OutputBuffer()
        let stderr = OutputBuffer()
        process.standardOutput = stdout.pipe
        process.standardError = stderr.pipe
        process.standardInput = FileHandle.nullDevice
        let timedOut = Flag()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                process.terminationHandler = { process in
                    let result = ShellResult(
                        exitCode: process.terminationStatus,
                        stdout: stdout.finish(),
                        stderr: stderr.finish()
                    )
                    if timedOut.isSet {
                        continuation.resume(throwing: ShellError.timedOut(timeout))
                    } else {
                        continuation.resume(returning: result)
                    }
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: ShellError.launchFailed(error.localizedDescription))
                    return
                }

                Task.detached {
                    try? await Task.sleep(for: timeout)
                    if process.isRunning {
                        timedOut.set()
                        process.terminate()
                    }
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}

/// Resolves PATH from an interactive login shell once and caches it.
///
/// GUI apps don't load ~/.zshrc, so tools installed via nvm/fnm/Homebrew
/// would otherwise be missing.
actor LoginEnvironment {
    static let shared = LoginEnvironment()

    private static let fallbackPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    private static let marker = "__DEVDOCK_PATH__"
    private var cachedPath: String?

    func path() async -> String {
        if let cachedPath { return cachedPath }

        // Shell startup files may print banners, so read only what follows the marker.
        // The user's login shell (zsh, bash, fish …) knows where their tools live.
        let shell = ProcessInfo.processInfo.environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
        let result = try? await ShellRunner.launch(
            executable: shell,
            arguments: ["-l", "-i", "-c", "printf '\(Self.marker)%s' \"$PATH\""],
            environment: ProcessInfo.processInfo.environment,
            currentDirectory: nil,
            timeout: .seconds(5)
        )
        let resolved = result?.stdout
            .components(separatedBy: Self.marker).last?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let path = (resolved?.isEmpty == false) ? resolved! : Self.fallbackPath
        cachedPath = path
        return path
    }
}

/// Collects a pipe's output while the process runs, so a full pipe buffer never blocks it.
private nonisolated final class OutputBuffer: @unchecked Sendable {
    let pipe = Pipe()
    private var data = Data()
    private let lock = NSLock()

    init() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            lock.withLock { data.append(chunk) }
        }
    }

    func finish() -> String {
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = nil
        let rest = handle.readDataToEndOfFile()
        return lock.withLock {
            data.append(rest)
            return String(decoding: data, as: UTF8.self)
        }
    }
}

private nonisolated final class Flag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()

    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}
