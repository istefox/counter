import Foundation
import Observation

@MainActor
@Observable
final class CodexUsageMonitor {
    private(set) var usage: CodexAccountRateLimits?
    private(set) var lastError: CodexUsageError?
    private(set) var isRefreshing = false
    private(set) var lastUpdated: Date?

    private let client: CodexAppServerClient
    private var pollingTask: Task<Void, Never>?

    init(client: CodexAppServerClient = CodexAppServerClient()) {
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
            usage = try await client.fetchRateLimits()
            lastError = nil
            lastUpdated = .now
        } catch let error as CodexUsageError {
            lastError = error
        } catch {
            lastError = .processFailed
        }
    }
}
