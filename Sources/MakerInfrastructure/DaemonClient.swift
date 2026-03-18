import Foundation
import Network

public struct DaemonClient: Sendable {
    public let port: UInt16

    public init(port: UInt16 = AppPaths.daemonPort) {
        self.port = port
    }

    public func send(_ request: DaemonRequest) async throws -> DaemonResponse {
        let endpointPort = try requirePort()
        let connection = NWConnection(host: .ipv4(.loopback), port: endpointPort, using: .tcp)
        connection.start(queue: .global(qos: .userInitiated))

        do {
            try await waitUntilReady(connection)
            let requestData = try JSONEncoder().encode(request) + Data([0x0A])
            try await send(data: requestData, over: connection)
            let responseData = try await receiveLine(over: connection)
            connection.cancel()
            return try JSONDecoder().decode(DaemonResponse.self, from: responseData)
        } catch {
            connection.cancel()
            throw error
        }
    }

    private func waitUntilReady(_ connection: NWConnection) async throws {
        try await withTimeout(seconds: 1.5) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        connection.stateUpdateHandler = nil
                        continuation.resume(returning: ())
                    case let .failed(error):
                        connection.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    case let .waiting(error):
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
    }

    private func requirePort() throws -> NWEndpoint.Port {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw CocoaError(.coderInvalidValue)
        }
        return port
    }

    private func send(data: Data, over connection: NWConnection) async throws {
        try await withTimeout(seconds: 1.5) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: data, completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: ())
                    }
                })
            }
        }
    }

    private func receiveLine(over connection: NWConnection) async throws -> Data {
        try await withTimeout(seconds: 1.5) {
            try await withCheckedThrowingContinuation { continuation in
                receiveLine(over: connection, accumulated: Data(), continuation: continuation)
            }
        }
    }

    private func receiveLine(
        over connection: NWConnection,
        accumulated: Data,
        continuation: CheckedContinuation<Data, Error>
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, isComplete, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                continuation.resume(returning: Data(buffer.prefix(upTo: newlineIndex)))
                return
            }

            if isComplete {
                continuation.resume(returning: buffer)
                return
            }

            receiveLine(over: connection, accumulated: buffer, continuation: continuation)
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
