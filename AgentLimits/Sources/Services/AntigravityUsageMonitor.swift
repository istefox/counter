import Foundation
import Observation

@MainActor
@Observable
final class AntigravityUsageMonitor {
    private(set) var usage: AntigravityUserStatus?
    private(set) var lastError: AntigravityUsageError?
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?

    private let client: AntigravityClient
    private var pollingTask: Task<Void, Never>?

    init(client: AntigravityClient = AntigravityClient()) {
        self.client = client
    }

    func startPolling(interval: Duration = .seconds(300)) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            usage = try await client.fetchUsage()
            lastError = nil
            lastUpdated = .now
        } catch let error as AntigravityUsageError {
            lastError = error
        } catch {
            lastError = .processFailed
        }
    }

    /// Terminates any language server process this app spawned itself. Called when
    /// the app is quitting, so a standalone Antigravity instance we own doesn't
    /// outlive AgentLimits.
    func shutdown() async {
        stopPolling()
        await client.terminateOwnedProcessIfAny()
    }
}
