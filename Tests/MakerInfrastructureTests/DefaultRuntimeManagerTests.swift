import Foundation
import Testing
import MakerAdapters
import MakerApplication
import MakerDomain
import MakerInfrastructure
import MakerSupport

@Test
func defaultRuntimeManagerAutoRestartsFailedSessionWhenProfileAllowsIt() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let adapter = ScriptedRuntimeAdapter()
    let sessions = InMemoryRunSessionRepository()
    let envSets = InMemoryEnvSetRepository()
    let secrets = InMemorySecretsStore()
    let logStore = LogFileStore(logsDirectory: root.appendingPathComponent("logs", isDirectory: true))
    let manager = DefaultRuntimeManager(
        adapterFactory: FixedRuntimeAdapterFactory(adapter: adapter),
        sessions: sessions,
        envSets: envSets,
        secrets: secrets,
        logStore: logStore
    )

    let project = Project(name: "Maker", localPath: root.path, status: .active)
    let profile = RuntimeProfile(
        projectID: project.id,
        name: "auto-restart",
        entryCommand: "echo",
        workingDir: root.path,
        autoRestart: true
    )

    let session = try await manager.start(project: project, profile: profile)
    await adapter.failWithExitCode(9)
    try await Task.sleep(for: .milliseconds(700))

    let stored = try await sessions.get(id: session.id)
    #expect(stored?.restartCount == 1)
    #expect(stored?.status == .running)
    #expect(stored?.pid == 22)
}

private actor ScriptedRuntimeAdapter: RuntimeAdapter {
    private var state: RuntimeProcessState = .idle
    private var lastExitCodeValue: Int32?
    private var startCount = 0

    func prepare(project: Project, profile: RuntimeProfile, env: [String : String]) async throws {
        state = .preparing
    }

    func start() async throws -> RuntimeExecutionHandle {
        startCount += 1
        state = .running
        let pid: Int32 = startCount == 1 ? 11 : 22
        return RuntimeExecutionHandle(pid: pid)
    }

    func stop() async throws {
        state = .stopped
    }

    func restart() async throws -> RuntimeExecutionHandle {
        try await start()
    }

    func getStatus() async -> RuntimeProcessState {
        state
    }

    func lastExitCode() async -> Int32? {
        lastExitCodeValue
    }

    nonisolated func streamLogs() -> AsyncThrowingStream<LogEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }

    func failWithExitCode(_ exitCode: Int32) {
        lastExitCodeValue = exitCode
        state = .failed
    }
}

private struct FixedRuntimeAdapterFactory: RuntimeAdapterFactory {
    let adapter: any RuntimeAdapter

    func makeAdapter(for profile: RuntimeProfile) -> any RuntimeAdapter {
        adapter
    }
}
