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
    private var activeProfiles: [RunSession.ID: RuntimeProfile] = [:]
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
        activeProfiles[session.id] = profile
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
            try await applyTerminalState(state, adapter: adapter, to: sessionID)
        }
        if var session = try await sessions.get(id: sessionID), session.status == .running {
            session.status = .stopped
            session.endedAt = Date()
            session.failureReason = nil
            try await sessions.update(session)
        }
        activeAdapters.removeValue(forKey: sessionID)
        activeProfiles.removeValue(forKey: sessionID)
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
        session.failureReason = nil
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
                case .failed:
                    if await restartIfNeeded(sessionID: sessionID, adapter: adapter) {
                        continue
                    }
                    try? await applyTerminalState(state, adapter: adapter, to: sessionID)
                    activeAdapters.removeValue(forKey: sessionID)
                    activeProfiles.removeValue(forKey: sessionID)
                    monitorTasks.removeValue(forKey: sessionID)
                    return
                case .stopped, .idle:
                    try? await applyTerminalState(state, adapter: adapter, to: sessionID)
                    activeAdapters.removeValue(forKey: sessionID)
                    activeProfiles.removeValue(forKey: sessionID)
                    monitorTasks.removeValue(forKey: sessionID)
                    return
                }
            }
        }
    }

    private func restartIfNeeded(sessionID: RunSession.ID, adapter: any RuntimeAdapter) async -> Bool {
        guard let profile = activeProfiles[sessionID], profile.autoRestart else {
            return false
        }
        guard let existingSession = try? await sessions.get(id: sessionID) else {
            return false
        }
        var session = existingSession

        do {
            let exitCode = await adapter.lastExitCode()
            let handle = try await adapter.restart()
            session.status = .running
            session.pid = handle.pid
            session.startedAt = Date()
            session.endedAt = nil
            session.exitCode = nil
            session.restartCount += 1
            session.failureReason = exitCode.map { "process exited with code \($0); auto-restarted" } ?? "process failed; auto-restarted"
            try await sessions.update(session)
            try? await logStore.append(
                LogEvent(stream: .system, message: "Auto-restarted session after failure"),
                sessionID: sessionID
            )
            return true
        } catch {
            return false
        }
    }

    private func applyTerminalState(_ state: RuntimeProcessState, adapter: any RuntimeAdapter, to sessionID: RunSession.ID) async throws {
        guard var session = try await sessions.get(id: sessionID) else {
            return
        }

        let exitCode = await adapter.lastExitCode()

        switch state {
        case .failed:
            session.status = .failed
            session.failureReason = exitCode.map { "process exited with code \($0)" } ?? "runtime process failed"
        case .stopped, .idle:
            session.status = .stopped
            if session.failureReason == "health check timeout" {
                session.status = .failed
            }
        case .running, .preparing:
            return
        }

        if session.endedAt == nil {
            session.endedAt = Date()
        }
        if session.exitCode == nil {
            session.exitCode = exitCode
        }
        try await sessions.update(session)
    }
}
