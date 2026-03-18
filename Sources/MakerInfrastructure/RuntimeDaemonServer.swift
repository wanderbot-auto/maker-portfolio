import Foundation
import MakerApplication
import MakerDomain
import Network

public final class RuntimeDaemonServer: @unchecked Sendable {
    private let services: CoreServices
    private let authToken: String
    private let port: UInt16
    private let queue = DispatchQueue(label: "MakerPortfolio.RuntimeDaemonServer")

    private var listener: NWListener?
    private var activeSessions: [RunSession.ID: RuntimeSessionSnapshot] = [:]

    public init(services: CoreServices, authToken: String, port: UInt16 = AppPaths.daemonPort) {
        self.services = services
        self.authToken = authToken
        self.port = port
    }

    public func start() throws {
        guard listener == nil else { return }
        guard let endpointPort = NWEndpoint.Port(rawValue: port) else {
            throw CocoaError(.coderInvalidValue)
        }

        let listener = try NWListener(using: .tcp, on: endpointPort)
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func run() throws -> Never {
        try start()
        while true {
            Thread.sleep(forTimeInterval: 3600)
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveLine(over: connection, accumulated: Data()) { [weak self] result in
            guard let self else { return }

            Task {
                let response: DaemonResponse
                switch result {
                case let .success(data):
                    response = await self.handleRequestData(data)
                case let .failure(error):
                    response = DaemonResponse(ok: false, message: error.localizedDescription)
                }
                self.send(response: response, over: connection)
                if response.message == "shutdown" {
                    self.queue.asyncAfter(deadline: .now() + 0.2) {
                        exit(0)
                    }
                }
            }
        }
    }

    private func handleRequestData(_ data: Data) async -> DaemonResponse {
        do {
            let request = try JSONDecoder().decode(DaemonRequest.self, from: data)
            guard request.token == authToken else {
                return DaemonResponse(ok: false, message: "unauthorized")
            }
            return try await route(request)
        } catch {
            return DaemonResponse(ok: false, message: error.localizedDescription)
        }
    }

    private func route(_ request: DaemonRequest) async throws -> DaemonResponse {
        switch request.action {
        case "ping":
            return DaemonResponse(ok: true, message: "pong")

        case "shutdown":
            listener?.cancel()
            listener = nil
            return DaemonResponse(ok: true, message: "shutdown")

        case "runtime.start":
            guard
                let projectID = request.projectID.flatMap(UUID.init(uuidString:)),
                let profileID = request.runtimeProfileID.flatMap(UUID.init(uuidString:))
            else {
                return DaemonResponse(ok: false, message: "invalid identifiers")
            }

            let session = try await StartRuntimeUseCase(
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                runtimeManager: services.runtimeManager
            ).execute(projectID: projectID, runtimeProfileID: profileID)

            let snapshot = RuntimeSessionSnapshot(
                sessionID: session.id,
                projectID: session.projectID,
                runtimeProfileID: session.runtimeProfileID,
                status: session.status,
                pid: session.pid
            )
            activeSessions[session.id] = snapshot
            return DaemonResponse(ok: true, message: "started", session: DaemonSessionSummary(snapshot: snapshot))

        case "runtime.stop":
            guard let sessionID = request.sessionID.flatMap(UUID.init(uuidString:)) else {
                return DaemonResponse(ok: false, message: "invalid session id")
            }

            try await StopRuntimeUseCase(runtimeManager: services.runtimeManager).execute(sessionID: sessionID)
            if var snapshot = activeSessions[sessionID] {
                snapshot.status = .stopped
                activeSessions[sessionID] = snapshot
                return DaemonResponse(ok: true, message: "stopped", session: DaemonSessionSummary(snapshot: snapshot))
            }

            if let snapshot = try await RuntimeStatusUseCase(sessions: services.runSessions).execute(sessionID: sessionID) {
                activeSessions.removeValue(forKey: sessionID)
                return DaemonResponse(ok: true, message: "stopped", session: DaemonSessionSummary(snapshot: snapshot))
            }
            return DaemonResponse(ok: true, message: "stopped")

        case "runtime.restart":
            guard let sessionID = request.sessionID.flatMap(UUID.init(uuidString:)) else {
                return DaemonResponse(ok: false, message: "invalid session id")
            }

            let session = try await RestartRuntimeUseCase(
                runtimeManager: services.runtimeManager,
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                sessions: services.runSessions
            ).execute(sessionID: sessionID)
            let snapshot = RuntimeSessionSnapshot(
                sessionID: session.id,
                projectID: session.projectID,
                runtimeProfileID: session.runtimeProfileID,
                status: session.status,
                pid: session.pid
            )
            activeSessions[session.id] = snapshot
            return DaemonResponse(ok: true, message: "restarted", session: DaemonSessionSummary(snapshot: snapshot))

        case "runtime.status":
            guard let sessionID = request.sessionID.flatMap(UUID.init(uuidString:)) else {
                return DaemonResponse(ok: false, message: "invalid session id")
            }

            if let snapshot = try await RuntimeStatusUseCase(sessions: services.runSessions).execute(sessionID: sessionID) {
                if snapshot.status == .running {
                    activeSessions[sessionID] = snapshot
                } else {
                    activeSessions.removeValue(forKey: sessionID)
                }
                return DaemonResponse(ok: true, message: "status", session: DaemonSessionSummary(snapshot: snapshot))
            }
            activeSessions.removeValue(forKey: sessionID)
            return DaemonResponse(ok: false, message: "session not found")

        case "runtime.active":
            var refreshed: [DaemonSessionSummary] = []
            for sessionID in activeSessions.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
                if let snapshot = try await RuntimeStatusUseCase(sessions: services.runSessions).execute(sessionID: sessionID),
                   snapshot.status == .running {
                    activeSessions[sessionID] = snapshot
                    refreshed.append(DaemonSessionSummary(snapshot: snapshot))
                } else {
                    activeSessions.removeValue(forKey: sessionID)
                }
            }
            return DaemonResponse(ok: true, message: "active", sessions: refreshed)

        case "runtime.history":
            guard let projectID = request.projectID.flatMap(UUID.init(uuidString:)) else {
                return DaemonResponse(ok: false, message: "invalid project id")
            }
            let limit = max(1, min(request.tail ?? 20, 200))
            let history = try await RuntimeHistoryUseCase(sessions: services.runSessions).execute(projectID: projectID, limit: limit)
            let summaries = history.map {
                DaemonSessionSummary(
                    sessionID: $0.sessionID.uuidString,
                    projectID: $0.projectID.uuidString,
                    runtimeProfileID: $0.runtimeProfileID.uuidString,
                    status: $0.status.rawValue,
                    pid: $0.pid
                )
            }
            return DaemonResponse(ok: true, message: "history", sessions: summaries)

        case "runtime.reconcile":
            let projectID = request.projectID.flatMap(UUID.init(uuidString:))
            let reconciled = try await ReconcileRuntimeSessionsUseCase(
                sessions: services.runSessions,
                processInspector: services.processInspector
            ).execute(projectID: projectID)

            let summaries = reconciled.map {
                DaemonSessionSummary(
                    sessionID: $0.sessionID.uuidString,
                    projectID: $0.projectID.uuidString,
                    runtimeProfileID: $0.runtimeProfileID.uuidString,
                    status: $0.currentStatus.rawValue,
                    pid: $0.pid
                )
            }

            for item in reconciled {
                activeSessions.removeValue(forKey: item.sessionID)
            }

            return DaemonResponse(ok: true, message: "reconciled \(reconciled.count)", sessions: summaries)

        case "runtime.logs":
            guard let sessionID = request.sessionID.flatMap(UUID.init(uuidString:)) else {
                return DaemonResponse(ok: false, message: "invalid session id")
            }
            let tail = max(1, min(request.tail ?? 50, 500))
            guard let snapshot = try await LoadRuntimeLogsUseCase(
                sessions: services.runSessions,
                logReader: services.logStore
            ).execute(sessionID: sessionID, tail: tail, afterLine: request.afterLine) else {
                return DaemonResponse(ok: false, message: "session not found")
            }

            let summary = DaemonSessionSummary(
                sessionID: snapshot.sessionID.uuidString,
                projectID: snapshot.projectID.uuidString,
                runtimeProfileID: snapshot.runtimeProfileID.uuidString,
                status: snapshot.status?.rawValue ?? "unknown",
                pid: snapshot.pid
            )
            return DaemonResponse(
                ok: true,
                message: "logs",
                session: summary,
                logs: snapshot.lines,
                nextLine: snapshot.nextLine
            )

        default:
            return DaemonResponse(ok: false, message: "unknown action")
        }
    }

    private func send(response: DaemonResponse, over connection: NWConnection) {
        do {
            let data = try JSONEncoder().encode(response) + Data([0x0A])
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        } catch {
            connection.cancel()
        }
    }

    private func receiveLine(
        over connection: NWConnection,
        accumulated: Data,
        completion: @Sendable @escaping (Result<Data, Error>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, error in
            if let error {
                completion(.failure(error))
                return
            }

            var buffer = accumulated
            if let data {
                buffer.append(data)
            }

            if let newlineIndex = buffer.firstIndex(of: 0x0A) {
                completion(.success(Data(buffer.prefix(upTo: newlineIndex))))
                return
            }

            if isComplete {
                completion(.success(buffer))
                return
            }

            self?.receiveLine(over: connection, accumulated: buffer, completion: completion)
        }
    }
}
