import Foundation
import MakerAdapters
import MakerApplication
import MakerDomain
import MakerSupport

public actor DefaultRuntimeManager: RuntimeManager {
    private let adapterFactory: any RuntimeAdapterFactory
    private let sessions: any RunSessionRepository
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore
    private let logStore: LogFileStore

    private var activeAdapters: [RunSession.ID: any RuntimeAdapter] = [:]
    private var monitorTasks: [RunSession.ID: Task<Void, Never>] = [:]

    public init(
        adapterFactory: any RuntimeAdapterFactory,
        sessions: any RunSessionRepository,
        envSets: any EnvSetRepository,
        secrets: any SecretsStore,
        logStore: LogFileStore
    ) {
        self.adapterFactory = adapterFactory
        self.sessions = sessions
        self.envSets = envSets
        self.secrets = secrets
        self.logStore = logStore
    }

    public func start(project: Project, profile: RuntimeProfile) async throws -> RunSession {
        let adapter = adapterFactory.makeAdapter(for: profile)
        let env = try await loadEnv(for: profile)

        try await adapter.prepare(project: project, profile: profile, env: env)
        let handle = try await adapter.start()

        let session = RunSession(
            projectID: project.id,
            runtimeProfileID: profile.id,
            status: .running,
            pid: handle.pid
        )
        try await sessions.save(session)
        activeAdapters[session.id] = adapter
        monitorTasks[session.id] = monitorLifecycle(for: session.id, adapter: adapter)
        attachLogStreaming(from: adapter, sessionID: session.id)
        return session
    }

    public func stop(sessionID: RunSession.ID) async throws {
        guard let adapter = activeAdapters[sessionID] else {
            return
        }
        do {
            try await adapter.stop()
        } catch MakerError.processNotRunning {
            let state = await adapter.getStatus()
            try await applyTerminalState(state, to: sessionID)
        }
        if var session = try await sessions.get(id: sessionID), session.status == .running {
            session.status = .stopped
            session.endedAt = Date()
            try await sessions.update(session)
        }
        activeAdapters.removeValue(forKey: sessionID)
        monitorTasks[sessionID]?.cancel()
        monitorTasks.removeValue(forKey: sessionID)
    }

    public func restart(sessionID: RunSession.ID) async throws -> RunSession {
        guard let adapter = activeAdapters[sessionID],
              var session = try await sessions.get(id: sessionID) else {
            throw MakerError.missingResource("No active runtime session for \(sessionID.uuidString)")
        }

        let handle = try await adapter.restart()
        session.status = .running
        session.pid = handle.pid
        session.startedAt = Date()
        session.endedAt = nil
        session.exitCode = nil
        try await sessions.update(session)
        return session
    }

    public func status(sessionID: RunSession.ID) async throws -> RunSessionStatus {
        if let session = try await sessions.get(id: sessionID) {
            return session.status
        }
        throw MakerError.missingResource("Run session \(sessionID.uuidString) not found")
    }

    public nonisolated func logs(sessionID: RunSession.ID) -> AsyncThrowingStream<LogEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    private func loadEnv(for profile: RuntimeProfile) async throws -> [String: String] {
        guard let envSetID = profile.envSetID else {
            return [:]
        }

        guard let envSet = try await envSets.get(id: envSetID) else {
            return [:]
        }

        if envSet.isEncrypted {
            return try await secrets.load(for: envSetID)
        }
        return envSet.variables
    }

    private func attachLogStreaming(from adapter: any RuntimeAdapter, sessionID: RunSession.ID) {
        Task {
            do {
                for try await event in adapter.streamLogs() {
                    try await logStore.append(event, sessionID: sessionID)
                }
            } catch {
                let fallback = LogEvent(stream: .system, message: "Log stream failed: \(error.localizedDescription)")
                try? await logStore.append(fallback, sessionID: sessionID)
            }
        }
    }

    private func monitorLifecycle(for sessionID: RunSession.ID, adapter: any RuntimeAdapter) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                let state = await adapter.getStatus()
                switch state {
                case .running, .preparing:
                    try? await Task.sleep(for: .milliseconds(300))
                case .stopped, .failed, .idle:
                    try? await applyTerminalState(state, to: sessionID)
                    activeAdapters.removeValue(forKey: sessionID)
                    monitorTasks.removeValue(forKey: sessionID)
                    return
                }
            }
        }
    }

    private func applyTerminalState(_ state: RuntimeProcessState, to sessionID: RunSession.ID) async throws {
        guard var session = try await sessions.get(id: sessionID) else {
            return
        }

        switch state {
        case .failed:
            session.status = .failed
        case .stopped, .idle:
            session.status = .stopped
        case .running, .preparing:
            return
        }

        if session.endedAt == nil {
            session.endedAt = Date()
        }
        try await sessions.update(session)
    }
}
