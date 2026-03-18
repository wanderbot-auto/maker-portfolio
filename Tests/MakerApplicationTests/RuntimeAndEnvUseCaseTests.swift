import Foundation
import Testing
import MakerApplication
import MakerDomain
import MakerSupport

@Test
func createProjectPersistsDiscoveredRuntimeProfilesWhenRepositoryProvided() async throws {
    let projects = ProjectRepositorySpy()
    let runtimeProfiles = RuntimeProfileRepositorySpy()
    let scanner = ProjectScannerWithProfilesStub()

    let useCase = CreateProjectUseCase(
        projects: projects,
        scanner: scanner,
        runtimeProfiles: runtimeProfiles
    )

    let project = try await useCase.execute(path: "/tmp/example")
    let storedProfiles = try await runtimeProfiles.list(projectID: project.id)

    #expect(storedProfiles.count == 2)
    #expect(storedProfiles.map(\.name) == ["api", "web"])
}

@Test
func listProjectsReturnsRuntimeCounts() async throws {
    let projects = ProjectRepositorySpy()
    let runtimeProfiles = RuntimeProfileRepositorySpy()
    let sessions = RunSessionRepositorySpy()

    let project = Project(name: "Maker", localPath: "/tmp/maker", status: .active)
    try await projects.save(project)
    try await runtimeProfiles.save(RuntimeProfile(projectID: project.id, name: "web", entryCommand: "npm", workingDir: "/tmp/maker"))
    try await runtimeProfiles.save(RuntimeProfile(projectID: project.id, name: "api", entryCommand: "swift", workingDir: "/tmp/maker"))

    let items = try await ListProjectsUseCase(
        projects: projects,
        runtimeProfiles: runtimeProfiles,
        sessions: sessions
    ).execute()

    #expect(items.count == 1)
    #expect(items.first?.runtimeCount == 2)
}

@Test
func upsertAndLoadEnvSetResolvesEncryptedValuesFromSecretsStore() async throws {
    let envSets = EnvSetRepositorySpy()
    let secrets = SecretsStoreSpy()
    let projectID = UUID()

    let envSet = try await UpsertEnvSetUseCase(envSets: envSets, secrets: secrets).execute(
        projectID: projectID,
        name: "local",
        variables: ["TOKEN": "secret"],
        encrypted: true
    )
    let snapshot = try await LoadEnvSetUseCase(envSets: envSets, secrets: secrets).execute(projectID: projectID, name: "local")

    #expect(envSet.isEncrypted == true)
    #expect(snapshot?.resolvedVariables["TOKEN"] == "secret")
}

@Test
func loadRuntimeLogsUseCaseReturnsRecentLinesForSession() async throws {
    let sessions = RunSessionRepositoryWithRecordSpy()
    let session = RunSession(
        projectID: UUID(),
        runtimeProfileID: UUID(),
        status: .stopped,
        pid: 42
    )
    try await sessions.save(session)
    let logReader = RuntimeLogReaderSpy(lines: ["one", "two", "three"])

    let snapshot = try await LoadRuntimeLogsUseCase(sessions: sessions, logReader: logReader)
        .execute(sessionID: session.id, tail: 2)

    #expect(snapshot?.sessionID == session.id)
    #expect(snapshot?.status == .stopped)
    #expect(snapshot?.lines == ["two", "three"])
}

@Test
func restartRuntimeUseCaseDelegatesToRuntimeManager() async throws {
    let expected = RunSession(
        id: UUID(),
        projectID: UUID(),
        runtimeProfileID: UUID(),
        status: .running,
        pid: 123
    )
    let runtimeManager = RuntimeManagerSpy(restartedSession: expected)

    let session = try await RestartRuntimeUseCase(runtimeManager: runtimeManager).execute(sessionID: expected.id)

    let restartedSessionID = runtimeManager.restartedSessionID
    #expect(restartedSessionID == expected.id)
    #expect(session.id == expected.id)
    #expect(session.pid == 123)
}

@Test
func restartRuntimeUseCaseFallsBackToStoredSessionProjectAndProfile() async throws {
    let project = Project(name: "Maker", localPath: "/tmp/maker", status: .active)
    let profile = RuntimeProfile(projectID: project.id, name: "web", entryCommand: "npm", workingDir: "/tmp/maker")
    let previousSession = RunSession(
        id: UUID(),
        projectID: project.id,
        runtimeProfileID: profile.id,
        status: .stopped,
        pid: 99
    )
    let restarted = RunSession(
        id: UUID(),
        projectID: project.id,
        runtimeProfileID: profile.id,
        status: .running,
        pid: 777
    )

    let runtimeManager = RuntimeManagerSpy(restartedSession: restarted, restartError: .missingResource("not active"))
    let projects = RestartProjectRepositorySpy(project: project)
    let profiles = RuntimeProfileRepositorySpy()
    try await profiles.save(profile)
    let sessions = RunSessionRepositoryWithRecordSpy()
    try await sessions.save(previousSession)

    let session = try await RestartRuntimeUseCase(
        runtimeManager: runtimeManager,
        projects: projects,
        runtimeProfiles: profiles,
        sessions: sessions
    ).execute(sessionID: previousSession.id)

    #expect(session.id == restarted.id)
    #expect(runtimeManager.startedProjectID == project.id)
    #expect(runtimeManager.startedProfileID == profile.id)
}

@Test
func runtimeHistoryUseCaseReturnsRepositoryOrderedSessions() async throws {
    let projectID = UUID()
    let recent = RunSession(
        id: UUID(),
        projectID: projectID,
        runtimeProfileID: UUID(),
        status: .stopped,
        pid: 1,
        startedAt: Date(timeIntervalSince1970: 2_000)
    )
    let earlier = RunSession(
        id: UUID(),
        projectID: projectID,
        runtimeProfileID: UUID(),
        status: .failed,
        pid: 2,
        startedAt: Date(timeIntervalSince1970: 1_000)
    )
    let sessions = RunSessionRepositorySpy(history: [recent, earlier])

    let history = try await RuntimeHistoryUseCase(sessions: sessions).execute(projectID: projectID, limit: 10)

    #expect(history.map(\.sessionID) == [recent.id, earlier.id])
    #expect(history.map(\.status) == [.stopped, .failed])
}

@Test
func reconcileRuntimeSessionsStopsDeadRunningSessions() async throws {
    let projectID = UUID()
    let session = RunSession(
        id: UUID(),
        projectID: projectID,
        runtimeProfileID: UUID(),
        status: .running,
        pid: 4321,
        startedAt: Date()
    )
    let sessions = RunSessionRepositoryWithRecordSpy()
    try await sessions.save(session)
    let inspector = ProcessInspectorSpy(runningPIDs: [])

    let reconciled = try await ReconcileRuntimeSessionsUseCase(
        sessions: sessions,
        processInspector: inspector
    ).execute(projectID: projectID)

    let stored = try await sessions.get(id: session.id)
    #expect(reconciled.count == 1)
    #expect(reconciled.first?.sessionID == session.id)
    #expect(stored?.status == .stopped)
    #expect(stored?.endedAt != nil)
}

actor RuntimeProfileRepositorySpy: RuntimeProfileRepository {
    private var profiles: [RuntimeProfile.ID: RuntimeProfile] = [:]

    func list(projectID: Project.ID) async throws -> [RuntimeProfile] {
        profiles.values.filter { $0.projectID == projectID }.sorted { $0.name < $1.name }
    }

    func get(id: RuntimeProfile.ID) async throws -> RuntimeProfile? {
        profiles[id]
    }

    func save(_ profile: RuntimeProfile) async throws {
        profiles[profile.id] = profile
    }

    func delete(id: RuntimeProfile.ID) async throws {
        profiles.removeValue(forKey: id)
    }
}

actor EnvSetRepositorySpy: EnvSetRepository {
    private var envSets: [EnvSet.ID: EnvSet] = [:]

    func list(projectID: Project.ID) async throws -> [EnvSet] {
        envSets.values.filter { $0.projectID == projectID }
    }

    func get(id: EnvSet.ID) async throws -> EnvSet? {
        envSets[id]
    }

    func save(_ envSet: EnvSet) async throws {
        envSets[envSet.id] = envSet
    }

    func delete(id: EnvSet.ID) async throws {
        envSets.removeValue(forKey: id)
    }
}

actor RunSessionRepositorySpy: RunSessionRepository {
    private let history: [RunSession]

    init(history: [RunSession] = []) {
        self.history = history
    }

    func list(projectID: Project.ID, limit: Int) async throws -> [RunSession] {
        Array(history.filter { $0.projectID == projectID }.prefix(limit))
    }

    func listRunning() async throws -> [RunSession] {
        history.filter { $0.status == .running }
    }

    func get(id: RunSession.ID) async throws -> RunSession? { nil }
    func save(_ session: RunSession) async throws {}
    func update(_ session: RunSession) async throws {}
}

actor RunSessionRepositoryWithRecordSpy: RunSessionRepository {
    private var storage: [RunSession.ID: RunSession] = [:]

    func list(projectID: Project.ID, limit: Int) async throws -> [RunSession] {
        Array(storage.values.prefix(limit))
    }

    func listRunning() async throws -> [RunSession] {
        storage.values.filter { $0.status == .running }
    }

    func get(id: RunSession.ID) async throws -> RunSession? {
        storage[id]
    }

    func save(_ session: RunSession) async throws {
        storage[session.id] = session
    }

    func update(_ session: RunSession) async throws {
        storage[session.id] = session
    }
}

actor SecretsStoreSpy: SecretsStore {
    private var values: [EnvSet.ID: [String: String]] = [:]

    func save(values: [String : String], for envSetID: EnvSet.ID) async throws {
        self.values[envSetID] = values
    }

    func load(for envSetID: EnvSet.ID) async throws -> [String : String] {
        values[envSetID] ?? [:]
    }

    func delete(for envSetID: EnvSet.ID) async throws {
        values.removeValue(forKey: envSetID)
    }
}

actor RestartProjectRepositorySpy: ProjectRepository {
    private let project: Project

    init(project: Project) {
        self.project = project
    }

    func list() async throws -> [Project] { [project] }
    func get(id: Project.ID) async throws -> Project? { id == project.id ? project : nil }
    func save(_ project: Project) async throws {}
    func archive(id: Project.ID, at: Date) async throws {}
}

struct RuntimeLogReaderSpy: RuntimeLogReader {
    let lines: [String]

    func readRecent(sessionID: RunSession.ID, tail: Int) async throws -> RuntimeLogChunk {
        RuntimeLogChunk(lines: Array(lines.suffix(tail)), nextLine: lines.count)
    }

    func readAfter(sessionID: RunSession.ID, line: Int) async throws -> RuntimeLogChunk {
        let safeIndex = max(0, min(line, lines.count))
        return RuntimeLogChunk(lines: Array(lines.dropFirst(safeIndex)), nextLine: lines.count)
    }
}

struct ProcessInspectorSpy: ProcessInspector {
    let runningPIDs: Set<Int32>

    func isProcessRunning(pid: Int32) async -> Bool {
        runningPIDs.contains(pid)
    }
}

final class RuntimeManagerSpy: @unchecked Sendable, RuntimeManager {
    let restartedSession: RunSession
    private let lock = NSLock()
    private var _restartedSessionID: RunSession.ID?
    private var _startedProjectID: Project.ID?
    private var _startedProfileID: RuntimeProfile.ID?
    private let restartError: MakerError?

    init(restartedSession: RunSession, restartError: MakerError? = nil) {
        self.restartedSession = restartedSession
        self.restartError = restartError
    }

    var restartedSessionID: RunSession.ID? {
        lock.withLock {
            _restartedSessionID
        }
    }

    var startedProjectID: Project.ID? {
        lock.withLock { _startedProjectID }
    }

    var startedProfileID: RuntimeProfile.ID? {
        lock.withLock { _startedProfileID }
    }

    func start(project: Project, profile: RuntimeProfile) async throws -> RunSession {
        lock.withLock {
            _startedProjectID = project.id
            _startedProfileID = profile.id
        }
        return restartedSession
    }

    func stop(sessionID: RunSession.ID) async throws {}

    func restart(sessionID: RunSession.ID) async throws -> RunSession {
        if let restartError {
            throw restartError
        }
        lock.withLock {
            _restartedSessionID = sessionID
        }
        return restartedSession
    }

    func status(sessionID: RunSession.ID) async throws -> RunSessionStatus {
        .running
    }

    nonisolated func logs(sessionID: RunSession.ID) -> AsyncThrowingStream<MakerSupport.LogEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

struct ProjectScannerWithProfilesStub: ProjectScanner {
    func scan(at path: String) async throws -> ProjectScanResult {
        ProjectScanResult(
            suggestedName: "Example",
            repoType: .git,
            stackSummary: "Swift / Node.js",
            discoveredProfiles: [
                DiscoveredRuntimeProfile(name: "web", entryCommand: "npm", workingDir: path, args: ["run", "dev"]),
                DiscoveredRuntimeProfile(name: "api", entryCommand: "swift", workingDir: path, args: ["run"])
            ]
        )
    }
}
