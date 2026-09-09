import Darwin
import Foundation

enum KeychainError: Error, Equatable {
    case unavailable(status: Int32)
    case launchFailed
    case readFailed
    case timeout
    case outputTooLarge
    case invalidCredentials
}

struct KeychainCredentialsReader: CredentialsSource {
    static let serviceName = "Claude Code-credentials"

    private let runCommand: ([String]) throws -> Data

    init(runCommand: @escaping ([String]) throws -> Data = {
        try CredentialCommandRunner.run(arguments: $0)
    }) {
        self.runCommand = runCommand
    }

    func readAccessToken() throws -> String {
        // Claude Code updates this item through security, which can reset its
        // partition list to apple-tool:. Use that same trusted system executable
        // instead of depending on a persistent grant to the AgentLimits binary.
        let data = try runCommand([
            "find-generic-password",
            "-s", Self.serviceName,
            "-a", NSUserName(),
            "-w"
        ])

        guard let decoded = try? JSONDecoder().decode(ClaudeCredentialsFile.self, from: data),
              !decoded.claudeAiOauth.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            // Do not propagate decoder diagnostics that could include credential data.
            throw KeychainError.invalidCredentials
        }
        return decoded.claudeAiOauth.accessToken
    }
}

/// Captures credentials only in memory. No shell, temporary file, or diagnostic
/// output is used. Nonblocking reads keep the deadline effective even when a
/// child stalls, closes stdout early, or fills the pipe.
enum CredentialCommandRunner {
    static func run(
        executableURL: URL = URL(fileURLWithPath: "/usr/bin/security"),
        arguments: [String],
        timeout: Duration = .seconds(5),
        maximumOutputBytes: Int = 1_048_576
    ) throws -> Data {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }

        let descriptor = output.fileHandleForReading.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags != -1, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) != -1 else {
            throw KeychainError.readFailed
        }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        do {
            try process.run()
        } catch {
            throw KeychainError.launchFailed
        }
        defer {
            // This child only reads credentials. Kill and reap it on failure so
            // a blocked Keychain prompt cannot accumulate background processes.
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            process.waitUntilExit()
        }
        try? output.fileHandleForWriting.close()

        let data = try captureOutput(
            from: descriptor, process: process, deadline: deadline,
            maximumOutputBytes: maximumOutputBytes
        )
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw KeychainError.unavailable(status: process.terminationStatus)
        }
        return data
    }

    private static func captureOutput(
        from descriptor: Int32,
        process: Process,
        deadline: ContinuousClock.Instant,
        maximumOutputBytes: Int
    ) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        var reachedEOF = false
        while !reachedEOF || process.isRunning {
            guard ContinuousClock.now < deadline else { throw KeychainError.timeout }
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= maximumOutputBytes - data.count else {
                    throw KeychainError.outputTooLarge
                }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                reachedEOF = true
                if process.isRunning {
                    Thread.sleep(forTimeInterval: 0.01)
                }
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                Thread.sleep(forTimeInterval: 0.01)
            } else if errno != EINTR {
                throw KeychainError.readFailed
            }
        }

        return data
    }
}
