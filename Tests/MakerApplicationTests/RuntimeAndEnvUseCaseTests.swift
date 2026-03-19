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
func projectDetailUseCaseLoadsRelatedResources() async throws {
    let projects = ProjectRepositorySpy()
    let runtimeProfiles = RuntimeProfileRepositorySpy()
    let envSets = EnvSetRepositorySpy()
    let sessions = RunSessionRepositoryWithRecordSpy()
    let milestones = MilestoneRepositorySpy()
    let notes = ProjectNoteRepositorySpy()

    let project = Project(name: "Maker", localPath: "/tmp/maker", status: .active)
    try await projects.save(project)
    try await runtimeProfiles.save(RuntimeProfile(projectID: project.id, name: "web", entryCommand: "npm", workingDir: "/tmp/maker"))
    try await envSets.save(EnvSet(projectID: project.id, name: "local", variables: ["BASE_URL": "http://localhost"], isEncrypted: false))
    try await sessions.save(RunSession(projectID: project.id, runtimeProfileID: UUID(), status: .running, pid: 7))
    try await milestones.save(Milestone(projectID: project.id, title: "Ship"))
    try await notes.save(ProjectNote(projectID: project.id, content: "Focus on CLI"))

    let snapshot = try await GetProjectDetailUseCase(
        projects: projects,
        runtimeProfiles: runtimeProfiles,
        envSets: envSets,
        sessions: sessions,
        milestones: milestones,
        notes: notes
    ).execute(projectID: project.id)

    #expect(snapshot?.project.id == project.id)
    #expect(snapshot?.runtimeProfiles.count == 1)
    #expect(snapshot?.envSets.count == 1)
    #expect(snapshot?.recentSessions.count == 1)
    #expect(snapshot?.milestones.count == 1)
    #expect(snapshot?.note?.content == "Focus on CLI")
}

@Test
func updateAndArchiveProjectUseCasesPersistChanges() async throws {
    let projects = ProjectRepositorySpy()
    let project = Project(name: "Maker", localPath: "/tmp/maker", status: .idea, priority: .p2)
    try await projects.save(project)

    let updated = try await UpdateProjectUseCase(projects: projects).execute(
        projectID: project.id,
        name: "Maker Core",
        description: "Stable local orchestrator",
        status: .active,
        priority: .p1
    )
    let archived = try await ArchiveProjectUseCase(projects: projects).execute(projectID: project.id)
    let restored = try await UnarchiveProjectUseCase(projects: projects).execute(projectID: project.id)

    #expect(updated.name == "Maker Core")
    #expect(updated.priority == .p1)
    #expect(archived.status == .archived)
    #expect(archived.archivedAt != nil)
    #expect(restored.status == .active)
    #expect(restored.archivedAt == nil)
}

@Test
func milestoneUseCasesCreateListAndUpdateState() async throws {
    let projects = ProjectRepositorySpy()
    let milestones = MilestoneRepositorySpy()
    let project = Project(name: "Maker", localPath: "/tmp/maker", status: .active)
    try await projects.save(project)

    let created = try await CreateMilestoneUseCase(
        projects: projects,
        milestones: milestones
    ).execute(projectID: project.id, title: "Ship CLI", dueDate: Date(timeIntervalSince1970: 1_700_000_000))

    let listed = try await ListMilestonesUseCase(
        projects: projects,
        milestones: milestones
    ).execute(projectID: project.id)

    let updated = try await UpdateMilestoneStateUseCase(
        milestones: milestones
    ).execute(milestoneID: created.id, state: .completed)

    #expect(listed.count == 1)
    #expect(listed.first?.title == "Ship CLI")
    #expect(listed.first?.dueDate == Date(timeIntervalSince1970: 1_700_000_000))
    #expect(updated.state == .completed)
}

@Test
func milestoneEditAndDeleteUseCasesPersistChanges() async throws {
    let milestones = MilestoneRepositorySpy()
    let milestone = Milestone(
        projectID: UUID(),
        title: "Ship CLI",
        dueDate: Date(timeIntervalSince1970: 1_700_000_000)
    )
    try await milestones.save(milestone)

    let edited = try await UpdateMilestoneUseCase(
        milestones: milestones
    ).execute(
        milestoneID: milestone.id,
        title: "Ship CLI v2",
        dueDate: .some(nil)
    )

    #expect(edited.title == "Ship CLI v2")
    #expect(edited.dueDate == nil)

    try await DeleteMilestoneUseCase(milestones: milestones).execute(milestoneID: milestone.id)

    let loaded = try await milestones.get(id: milestone.id)
    #expect(loaded == nil)
}

@Test
func rescanProjectUseCaseRefreshesMetadataAndAddsMissingProfiles() async throws {
    let projects = ProjectRepositorySpy()
    let runtimeProfiles = RuntimeProfileRepositorySpy()
    let project = Project(name: "Maker", localPath: "/tmp/maker", repoType: .localOnly, stackSummary: "Unknown")
    try await projects.save(project)
    try await runtimeProfiles.save(RuntimeProfile(projectID: project.id, name: "web", entryCommand: "npm", workingDir: "/tmp/maker", args: ["run", "dev"]))

    let result = try await RescanProjectUseCase(
        projects: projects,
        runtimeProfiles: runtimeProfiles,
        scanner: ProjectRescanScannerStub()
    ).execute(projectID: project.id)
    let profiles = try await runtimeProfiles.list(projectID: project.id)

    #expect(result.project.repoType == .git)
    #expect(result.project.stackSummary == "Swift / Node.js")
    #expect(result.createdProfiles.count == 1)
    #expect(profiles.count == 2)
    #expect(profiles.map(\.name).sorted() == ["api", "web"])
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
func listCopyUnsetAndDeleteEnvSetUseCasesManageVariables() async throws {
    let envSets = EnvSetRepositorySpy()
    let secrets = SecretsStoreSpy()
    let projectID = UUID()

    _ = try await UpsertEnvSetUseCase(envSets: envSets, secrets: secrets).execute(
        projectID: projectID,
        name: "local",
        variables: ["TOKEN": "secret", "BASE_URL": "http://localhost"],
        encrypted: true
    )

    let listed = try await ListEnvSetsUseCase(envSets: envSets, secrets: secrets).execute(projectID: projectID)
    let copied = try await CopyEnvSetUseCase(envSets: envSets, secrets: secrets).execute(
        projectID: projectID,
        sourceName: "local",
        targetName: "staging"
    )
    let updated = try await UnsetEnvVariablesUseCase(envSets: envSets, secrets: secrets).execute(
        projectID: projectID,
        name: "staging",
        keys: ["TOKEN"]
    )
    let deleted = try await DeleteEnvSetUseCase(envSets: envSets, secrets: secrets).execute(
        projectID: projectID,
        name: "local"
    )
    let remaining = try await envSets.list(projectID: projectID)

    #expect(listed.count == 1)
    #expect(copied?.resolvedVariables["TOKEN"] == "secret")
    #expect(updated?.resolvedVariables.keys.sorted() == ["BASE_URL"])
    #expect(deleted?.name == "local")
    #expect(remaining.count == 1)
}

@Test
func createUpdateAndDeleteRuntimeProfileUseCasesManageProfiles() async throws {
    let runtimeProfiles = RuntimeProfileRepositorySpy()
    let projectID = UUID()

    let created = try await CreateRuntimeProfileUseCase(runtimeProfiles: runtimeProfiles).execute(
        projectID: projectID,
        name: "api",
        entryCommand: "swift",
        workingDir: "/tmp/api",
        args: ["run"]
    )
    let updated = try await UpdateRuntimeProfileUseCase(runtimeProfiles: runtimeProfiles).execute(
        profileID: created.id,
        name: "api-dev",
        entryCommand: "swift",
        workingDir: "/tmp/api",
        args: ["run", "--debug"]
    )
    let loaded = try await GetRuntimeProfileUseCase(runtimeProfiles: runtimeProfiles).execute(profileID: created.id)
    try await DeleteRuntimeProfileUseCase(runtimeProfiles: runtimeProfiles).execute(profileID: created.id)

    #expect(updated.name == "api-dev")
    #expect(updated.args == ["run", "--debug"])
    #expect(loaded?.name == "api-dev")
    #expect(try await runtimeProfiles.get(id: created.id) == nil)
}

@Test
func runtimeProfileEnvDependencyHealthAndRestartUseCasesUpdateFields() async throws {
    let runtimeProfiles = RuntimeProfileRepositorySpy()
    let envSets = EnvSetRepositorySpy()
    let projectID = UUID()

    let profile = RuntimeProfile(projectID: projectID, name: "api", entryCommand: "swift", workingDir: "/tmp/api")
    let dependency = RuntimeProfile(projectID: projectID, name: "db", entryCommand: "postgres", workingDir: "/tmp/db")
    let envSet = EnvSet(projectID: projectID, name: "local", variables: [:], isEncrypted: true)
    try await runtimeProfiles.save(profile)
    try await runtimeProfiles.save(dependency)
    try await envSets.save(envSet)

    let attached = try await AttachEnvSetToRuntimeProfileUseCase(
        runtimeProfiles: runtimeProfiles,
        envSets: envSets
    ).execute(profileID: profile.id, envSetID: envSet.id)
    let withDependency = try await AddRuntimeProfileDependencyUseCase(runtimeProfiles: runtimeProfiles).execute(
        profileID: profile.id,
        dependsOnProfileID: dependency.id
    )
    let withHealth = try await SetRuntimeProfileHealthCheckUseCase(runtimeProfiles: runtimeProfiles).execute(
        profileID: profile.id,
        type: .http,
        target: "http://localhost:3000/health"
    )
    let withAutoRestart = try await SetRuntimeProfileAutoRestartUseCase(runtimeProfiles: runtimeProfiles).execute(
        profileID: profile.id,
        enabled: true
    )
    let withoutDependency = try await RemoveRuntimeProfileDependencyUseCase(runtimeProfiles: runtimeProfiles).execute(
        profileID: profile.id,
        dependsOnProfileID: dependency.id
    )
    let detached = try await DetachEnvSetFromRuntimeProfileUseCase(runtimeProfiles: runtimeProfiles).execute(profileID: profile.id)

    #expect(attached.envSetID == envSet.id)
    #expect(withDependency.dependsOn == [dependency.id])
    #expect(withHealth.healthCheckType == .http)
    #expect(withHealth.healthCheckTarget == "http://localhost:3000/health")
    #expect(withAutoRestart.autoRestart == true)
    #expect(withoutDependency.dependsOn.isEmpty)
    #expect(detached.envSetID == nil)
}

@Test
func saveAndLoadProjectNoteUseCasesRoundTripContent() async throws {
    let notes = ProjectNoteRepositorySpy()
    let projectID = UUID()

    let saved = try await SaveProjectNoteUseCase(notes: notes).execute(projectID: projectID, content: "CLI first")
    let loaded = try await LoadProjectNoteUseCase(notes: notes).execute(projectID: projectID)

    #expect(saved.content == "CLI first")
    #expect(loaded?.content == "CLI first")
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
func listRuntimeSessionsUseCaseFiltersByProjectAndStatus() async throws {
    let projectID = UUID()
    let otherProjectID = UUID()
    let running = RunSession(
        id: UUID(),
        projectID: projectID,
        runtimeProfileID: UUID(),
        status: .running,
        pid: 10,
        startedAt: Date(timeIntervalSince1970: 2_000)
    )
    let stopped = RunSession(
        id: UUID(),
        projectID: projectID,
        runtimeProfileID: UUID(),
        status: .stopped,
        pid: 11,
        startedAt: Date(timeIntervalSince1970: 1_500)
    )
    let otherProject = RunSession(
        id: UUID(),
        projectID: otherProjectID,
        runtimeProfileID: UUID(),
        status: .failed,
        pid: 12,
        startedAt: Date(timeIntervalSince1970: 1_000)
    )
    let sessions = RunSessionRepositorySpy(history: [running, stopped, otherProject])

    let filteredByProject = try await ListRuntimeSessionsUseCase(sessions: sessions).execute(projectID: projectID, limit: 10)
    let filteredByStatus = try await ListRuntimeSessionsUseCase(sessions: sessions).execute(status: .failed, limit: 10)

    #expect(filteredByProject.map(\.id) == [running.id, stopped.id])
    #expect(filteredByStatus.map(\.id) == [otherProject.id])
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

@Test
func diagnoseRuntimeSessionsReportsWhetherPidsAreAlive() async throws {
    let runningProjectID = UUID()
    let runningSession = RunSession(
        id: UUID(),
        projectID: runningProjectID,
        runtimeProfileID: UUID(),
        status: .running,
        pid: 1234,
        startedAt: Date()
    )
    let missingPIDSession = RunSession(
        id: UUID(),
        projectID: UUID(),
        runtimeProfileID: UUID(),
        status: .running,
        pid: nil,
        startedAt: Date()
    )
    let sessions = RunSessionRepositoryWithRecordSpy()
    try await sessions.save(runningSession)
    try await sessions.save(missingPIDSession)

    let items = try await DiagnoseRuntimeSessionsUseCase(
        sessions: sessions,
        processInspector: ProcessInspectorSpy(runningPIDs: [1234])
    ).execute()

    #expect(items.count == 2)
    #expect(items.first(where: { $0.sessionID == runningSession.id })?.processRunning == true)
    #expect(items.first(where: { $0.sessionID == missingPIDSession.id })?.processRunning == false)
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

actor MilestoneRepositorySpy: MilestoneRepository {
    private var storage: [Milestone.ID: Milestone] = [:]

    func list(projectID: Project.ID) async throws -> [Milestone] {
        storage.values.filter { $0.projectID == projectID }
    }

    func get(id: Milestone.ID) async throws -> Milestone? {
        storage[id]
    }

    func save(_ milestone: Milestone) async throws {
        storage[milestone.id] = milestone
    }

    func delete(id: Milestone.ID) async throws {
        storage.removeValue(forKey: id)
    }
}

actor ProjectNoteRepositorySpy: ProjectNoteRepository {
    private var storage: [Project.ID: ProjectNote] = [:]

    func get(projectID: Project.ID) async throws -> ProjectNote? {
        storage[projectID]
    }

    func save(_ note: ProjectNote) async throws {
        storage[note.projectID] = note
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

    func listAll(limit: Int, status: RunSessionStatus?) async throws -> [RunSession] {
        Array(
            history
                .filter { status == nil || $0.status == status }
                .prefix(limit)
        )
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
        Array(
            storage.values
                .filter { $0.projectID == projectID }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    func listAll(limit: Int, status: RunSessionStatus?) async throws -> [RunSession] {
        Array(
            storage.values
                .filter { status == nil || $0.status == status }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
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

struct ProjectRescanScannerStub: ProjectScanner {
    func scan(at path: String) async throws -> ProjectScanResult {
        ProjectScanResult(
            suggestedName: "Maker",
            repoType: .git,
            stackSummary: "Swift / Node.js",
            discoveredProfiles: [
                DiscoveredRuntimeProfile(name: "web", entryCommand: "npm", workingDir: path, args: ["run", "dev"]),
                DiscoveredRuntimeProfile(name: "api", entryCommand: "swift", workingDir: path, args: ["run"])
            ]
        )
    }
}
