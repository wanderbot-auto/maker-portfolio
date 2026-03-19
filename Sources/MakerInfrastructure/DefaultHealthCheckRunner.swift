import Foundation
import MakerApplication
import MakerDomain
import Network

public struct DefaultHealthCheckRunner: HealthCheckRunner {
    public let processInspector: any ProcessInspector

    public init(processInspector: any ProcessInspector) {
        self.processInspector = processInspector
    }

    public func evaluate(profile: RuntimeProfile, session: RunSession) async -> HealthCheckResult {
        switch profile.healthCheckType {
        case .none:
            return HealthCheckResult(status: .passing, detail: "health check disabled")

        case .processExists:
            guard let pid = session.pid else {
                return HealthCheckResult(status: .failing, detail: "session pid is missing")
            }
            let running = await processInspector.isProcessRunning(pid: pid)
            return HealthCheckResult(
                status: running ? .passing : .failing,
                detail: running ? "process \(pid) is running" : "process \(pid) is not running"
            )

        case .http:
            guard let target = profile.healthCheckTarget, let url = URL(string: target) else {
                return HealthCheckResult(status: .failing, detail: "invalid http target")
            }
            return await evaluateHTTP(url: url)

        case .tcp:
            guard let target = profile.healthCheckTarget else {
                return HealthCheckResult(status: .failing, detail: "missing tcp target")
            }
            return await evaluateTCP(target: target)
        }
    }

    private func evaluateHTTP(url: URL) async -> HealthCheckResult {
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse, (200..<400).contains(httpResponse.statusCode) {
                return HealthCheckResult(status: .passing, detail: "http \(httpResponse.statusCode)")
            }
            if let httpResponse = response as? HTTPURLResponse {
                return HealthCheckResult(status: .failing, detail: "http \(httpResponse.statusCode)")
            }
            return HealthCheckResult(status: .failing, detail: "non-http response")
        } catch {
            return HealthCheckResult(status: .failing, detail: error.localizedDescription)
        }
    }

    private func evaluateTCP(target: String) async -> HealthCheckResult {
        let parts = target.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let portValue = UInt16(parts[1]), let port = NWEndpoint.Port(rawValue: portValue) else {
            return HealthCheckResult(status: .failing, detail: "invalid tcp target")
        }

        let host = NWEndpoint.Host(parts[0])
        let connection = NWConnection(host: host, port: port, using: .tcp)
        connection.start(queue: .global(qos: .utility))

        do {
            try await withTimeout(seconds: 1.5) {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            connection.stateUpdateHandler = nil
                            continuation.resume(returning: ())
                        case let .failed(error), let .waiting(error):
                            connection.stateUpdateHandler = nil
                            continuation.resume(throwing: error)
                        case .cancelled:
                            connection.stateUpdateHandler = nil
                            continuation.resume(throwing: URLError(.cancelled))
                        default:
                            break
                        }
                    }
                }
            }
            connection.cancel()
            return HealthCheckResult(status: .passing, detail: "tcp ready")
        } catch {
            connection.cancel()
            return HealthCheckResult(status: .failing, detail: error.localizedDescription)
        }
    }

    private func withTimeout<T: Sendable>(
        seconds: Double,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw URLError(.timedOut)
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
