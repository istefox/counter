import Foundation

enum AntigravityUsageError: Error, Equatable {
    case antigravityNotInstalled
    case processFailed
    case decoding
    case timeout
}

/// Google Antigravity's bundled `language_server` binary exposes account/quota data
/// over Connect-RPC on a local HTTPS port. This is an undocumented internal protocol
/// (unlike Codex's published JSON-RPC schema), reverse-engineered from Nimbalyst's
/// open-source `AntigravityServerManager.ts`/`AntigravityUsageMeter.ts` and verified
/// live in this session: spawned a standalone instance with the arguments below,
/// confirmed `Heartbeat` and `GetUserStatus` both respond 200 with real account data.
///
/// Two ways to reach a live endpoint: attach to an already-running hub (the
/// Antigravity IDE is open) discovered via `ps`/`lsof`, or spawn our own standalone
/// instance. A spawned instance takes several seconds to become healthy, so unlike
/// Codex's per-refresh spawn/terminate, an owned process is kept alive across polls
/// and only torn down on `terminateOwnedProcessIfAny()` (called when the app quits).
actor AntigravityClient {
    private static let binaryPath = "/Applications/Antigravity.app/Contents/Resources/bin/language_server"
    private static let service = "exa.language_server_pb.LanguageServerService"
    private static let spawnPortCandidates = [51717, 8765, 13456, 21345, 31987, 41234]
    private static let overrideIdeVersion = "2.1.4"
    private static let spawnHealthyTimeout: TimeInterval = 30
    private static let requestTimeout: TimeInterval = 15

    private var endpoint: (port: Int, csrf: String)?
    private var ownedProcess: Process?

    func fetchUsage() async throws -> AntigravityUserStatus {
        guard FileManager.default.isExecutableFile(atPath: Self.binaryPath) else {
            throw AntigravityUsageError.antigravityNotInstalled
        }

        let ep = try await resolveEndpoint()
        do {
            let data = try await Self.withTimeout(Self.requestTimeout) {
                try await self.rpc(method: "GetUserStatus", endpoint: ep)
            }
            return try JSONDecoder()
                .decode(UserStatusEnvelope.self, from: data)
                .userStatus
        } catch is DecodingError {
            throw AntigravityUsageError.decoding
        } catch let error as AntigravityUsageError {
            throw error
        } catch {
            throw AntigravityUsageError.timeout
        }
    }

    /// Terminates a process this actor spawned itself. No-op when attached to an
    /// externally-owned hub (the IDE), or when nothing has been spawned yet.
    func terminateOwnedProcessIfAny() {
        ownedProcess?.terminate()
        ownedProcess = nil
        endpoint = nil
    }

    // MARK: - Endpoint resolution

    private func resolveEndpoint() async throws -> (port: Int, csrf: String) {
        if let endpoint, await isHealthy(endpoint) {
            return endpoint
        }
        endpoint = nil

        if let discovered = await discoverRunningHub() {
            endpoint = discovered
            return discovered
        }

        let spawned = try await spawnStandalone()
        endpoint = spawned
        return spawned
    }

    private func discoverRunningHub() async -> (port: Int, csrf: String)? {
        guard let psOutput = try? Self.runCommand("/bin/ps", ["-axww", "-o", "pid=,command="]) else {
            return nil
        }

        for hub in Self.parseHubProcesses(psOutput) {
            guard let lsofOutput = try? Self.runCommand(
                "/usr/sbin/lsof",
                ["-nP", "-a", "-p", String(hub.pid), "-iTCP", "-sTCP:LISTEN", "-F", "n"]
            ) else { continue }

            for port in Self.parseListenerPorts(lsofOutput) {
                let candidate = (port: port, csrf: hub.csrf)
                if await isHealthy(candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func spawnStandalone() async throws -> (port: Int, csrf: String) {
        for port in Self.spawnPortCandidates {
            let csrf = "AgentLimits-\(UUID().uuidString)"
            let process = Process()
            process.executableURL = URL(fileURLWithPath: Self.binaryPath)
            process.arguments = [
                "--standalone",
                "--subclient_type", "hub",
                "--override_ide_name", "antigravity",
                "--override_ide_version", Self.overrideIdeVersion,
                "--override_user_agent_name", "antigravity",
                "--api_server_url", "https://generativelanguage.googleapis.com",
                "--cloud_code_endpoint", "https://daily-cloudcode-pa.googleapis.com",
                "--csrf_token", csrf,
                "--https_server_port", String(port),
                "--app_data_dir", "antigravity",
                "--enable_sidecars",
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
            } catch {
                continue
            }

            let candidate = (port: port, csrf: csrf)
            let deadline = Date().addingTimeInterval(Self.spawnHealthyTimeout)
            while Date() < deadline {
                if !process.isRunning { break }
                if await isHealthy(candidate) {
                    ownedProcess = process
                    return candidate
                }
                try? await Task.sleep(for: .milliseconds(500))
            }
            process.terminate()
        }
        throw AntigravityUsageError.processFailed
    }

    // MARK: - RPC

    private func isHealthy(_ endpoint: (port: Int, csrf: String)) async -> Bool {
        (try? await rpc(method: "Heartbeat", endpoint: endpoint)) != nil
    }

    private func rpc(method: String, endpoint: (port: Int, csrf: String)) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://127.0.0.1:\(endpoint.port)/\(Self.service)/\(method)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(endpoint.csrf, forHTTPHeaderField: "x-codeium-csrf-token")
        request.httpBody = Data("{}".utf8)

        let session = URLSession(
            configuration: .ephemeral,
            delegate: LocalhostTrustingDelegate(),
            delegateQueue: nil
        )
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AntigravityUsageError.processFailed
        }
        return data
    }

    private static func withTimeout<T: Sendable>(
        _ seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw AntigravityUsageError.timeout
            }
            guard let result = try await group.next() else {
                throw AntigravityUsageError.timeout
            }
            group.cancelAll()
            return result
        }
    }

    /// `ps -axww` output on this machine regularly exceeds the OS pipe buffer (long
    /// command lines from shell wrapper scripts). Reading via `readDataToEndOfFile()`
    /// BEFORE `waitUntilExit()` drains the pipe as the child writes, avoiding the
    /// classic deadlock where the child blocks on a full pipe while the parent blocks
    /// on `waitUntilExit()` without ever reading it.
    private static func runCommand(_ executable: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func parseHubProcesses(_ psOutput: String) -> [(pid: Int32, csrf: String)] {
        var hubs: [(pid: Int32, csrf: String)] = []
        for line in psOutput.split(separator: "\n") {
            guard let spaceIndex = line.firstIndex(of: " "),
                  let pid = Int32(line[line.startIndex..<spaceIndex])
            else { continue }
            let command = String(line[spaceIndex...])
            guard command.contains("language_server"),
                  command.contains("--subclient_type hub"),
                  command.contains("--app_data_dir antigravity"),
                  let csrf = Self.extractArgument("--csrf_token", from: command)
            else { continue }
            hubs.append((pid: pid, csrf: csrf))
        }
        return hubs
    }

    private static func extractArgument(_ flag: String, from command: String) -> String? {
        guard let range = command.range(of: "\(flag) ") else { return nil }
        let rest = command[range.upperBound...]
        return rest.split(separator: " ").first.map(String.init)
    }

    private static func parseListenerPorts(_ lsofOutput: String) -> [Int] {
        var ports = Set<Int>()
        for line in lsofOutput.split(separator: "\n") where line.hasPrefix("n") {
            guard let colonIndex = line.lastIndex(of: ":"),
                  let port = Int(line[line.index(after: colonIndex)...])
            else { continue }
            ports.insert(port)
        }
        return ports.sorted()
    }
}

private struct UserStatusEnvelope: Decodable {
    let userStatus: AntigravityUserStatus
}

/// The language server serves a self-signed certificate on 127.0.0.1. This delegate
/// trusts it only for that exact host, never for any other host this session might
/// reach through `URLSession`.
private final class LocalhostTrustingDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.host == "127.0.0.1",
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
