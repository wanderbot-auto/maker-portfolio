import Foundation
import MakerDomain
import MakerSupport

public struct CreateProjectUseCase: Sendable {
    private let projects: any ProjectRepository
    private let scanner: any ProjectScanner
    private let runtimeProfiles: (any RuntimeProfileRepository)?

    public init(
        projects: any ProjectRepository,
        scanner: any ProjectScanner,
        runtimeProfiles: (any RuntimeProfileRepository)? = nil
    ) {
        self.projects = projects
        self.scanner = scanner
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(path: String, description: String = "", tags: [String] = []) async throws -> Project {
        let scanResult = try await scanner.scan(at: path)
        let project = Project(
            name: scanResult.suggestedName,
            localPath: path,
            repoType: scanResult.repoType,
            description: description,
            tags: tags,
            stackSummary: scanResult.stackSummary
        )
        try await projects.save(project)
        if let runtimeProfiles {
            for discovered in scanResult.discoveredProfiles {
                let profile = RuntimeProfile(
                    projectID: project.id,
                    name: discovered.name,
                    entryCommand: discovered.entryCommand,
                    workingDir: discovered.workingDir,
                    args: discovered.args
                )
                try await runtimeProfiles.save(profile)
            }
        }
        return project
    }
}

public struct ListProjectsUseCase: Sendable {
    private let projects: any ProjectRepository
    private let runtimeProfiles: any RuntimeProfileRepository
    private let sessions: any RunSessionRepository

    public init(
        projects: any ProjectRepository,
        runtimeProfiles: any RuntimeProfileRepository,
        sessions: any RunSessionRepository
    ) {
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.sessions = sessions
    }

    public func execute() async throws -> [ProjectListItem] {
        let projects = try await projects.list()
        var items: [ProjectListItem] = []

        for project in projects {
            let profiles = try await runtimeProfiles.list(projectID: project.id)
            let latestSession = try await sessions.list(projectID: project.id, limit: 1).first
            items.append(
                ProjectListItem(
                    project: project,
                    runtimeCount: profiles.count,
                    latestSession: latestSession
                )
            )
        }

        return items
    }
}

public struct ListRuntimeProfilesUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(projectID: Project.ID) async throws -> [RuntimeProfile] {
        try await runtimeProfiles.list(projectID: projectID)
    }
}

public struct StartRuntimeUseCase: Sendable {
    private let projects: any ProjectRepository
    private let runtimeProfiles: any RuntimeProfileRepository
    private let runtimeManager: any RuntimeManager

    public init(
        projects: any ProjectRepository,
        runtimeProfiles: any RuntimeProfileRepository,
        runtimeManager: any RuntimeManager
    ) {
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.runtimeManager = runtimeManager
    }

    public func execute(projectID: Project.ID, runtimeProfileID: RuntimeProfile.ID) async throws -> RunSession {
        guard let project = try await projects.get(id: projectID) else {
            throw NSError(domain: "MakerApplication.StartRuntimeUseCase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Project not found"])
        }
        guard let profile = try await runtimeProfiles.get(id: runtimeProfileID) else {
            throw NSError(domain: "MakerApplication.StartRuntimeUseCase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Runtime profile not found"])
        }
        return try await runtimeManager.start(project: project, profile: profile)
    }
}

public struct StopRuntimeUseCase: Sendable {
    private let runtimeManager: any RuntimeManager

    public init(runtimeManager: any RuntimeManager) {
        self.runtimeManager = runtimeManager
    }

    public func execute(sessionID: RunSession.ID) async throws {
        try await runtimeManager.stop(sessionID: sessionID)
    }
}

public struct RestartRuntimeUseCase: Sendable {
    private let runtimeManager: any RuntimeManager
    private let projects: (any ProjectRepository)?
    private let runtimeProfiles: (any RuntimeProfileRepository)?
    private let sessions: (any RunSessionRepository)?

    public init(
        runtimeManager: any RuntimeManager,
        projects: (any ProjectRepository)? = nil,
        runtimeProfiles: (any RuntimeProfileRepository)? = nil,
        sessions: (any RunSessionRepository)? = nil
    ) {
        self.runtimeManager = runtimeManager
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.sessions = sessions
    }

    public func execute(sessionID: RunSession.ID) async throws -> RunSession {
        do {
            return try await runtimeManager.restart(sessionID: sessionID)
        } catch let error as MakerError {
            guard case .missingResource = error else {
                throw error
            }

            guard
                let projects,
                let runtimeProfiles,
                let sessions,
                let previousSession = try await sessions.get(id: sessionID),
                let project = try await projects.get(id: previousSession.projectID),
                let profile = try await runtimeProfiles.get(id: previousSession.runtimeProfileID)
            else {
                throw error
            }

            return try await runtimeManager.start(project: project, profile: profile)
        }
    }
}

public struct RuntimeStatusUseCase: Sendable {
    private let sessions: any RunSessionRepository

    public init(sessions: any RunSessionRepository) {
        self.sessions = sessions
    }

    public func execute(sessionID: RunSession.ID) async throws -> RuntimeSessionSnapshot? {
        guard let session = try await sessions.get(id: sessionID) else {
            return nil
        }
        return RuntimeSessionSnapshot(
            sessionID: session.id,
            projectID: session.projectID,
            runtimeProfileID: session.runtimeProfileID,
            status: session.status,
            pid: session.pid
        )
    }
}

public struct RuntimeHistoryUseCase: Sendable {
    private let sessions: any RunSessionRepository

    public init(sessions: any RunSessionRepository) {
        self.sessions = sessions
    }

    public func execute(projectID: Project.ID, limit: Int) async throws -> [RuntimeHistoryItem] {
        try await sessions.list(projectID: projectID, limit: limit).map(RuntimeHistoryItem.init(session:))
    }
}

public struct ReconcileRuntimeSessionsUseCase: Sendable {
    private let sessions: any RunSessionRepository
    private let processInspector: any ProcessInspector

    public init(sessions: any RunSessionRepository, processInspector: any ProcessInspector) {
        self.sessions = sessions
        self.processInspector = processInspector
    }

    public func execute(projectID: Project.ID? = nil) async throws -> [RuntimeReconcileItem] {
        let running = try await sessions.listRunning()
        var reconciled: [RuntimeReconcileItem] = []

        for var session in running {
            if let projectID, session.projectID != projectID {
                continue
            }

            let stillRunning: Bool
            if let pid = session.pid {
                stillRunning = await processInspector.isProcessRunning(pid: pid)
            } else {
                stillRunning = false
            }

            guard stillRunning == false else {
                continue
            }

            let previousStatus = session.status
            session.status = .stopped
            if session.endedAt == nil {
                session.endedAt = Date()
            }
            try await sessions.update(session)
            reconciled.append(
                RuntimeReconcileItem(
                    sessionID: session.id,
                    projectID: session.projectID,
                    runtimeProfileID: session.runtimeProfileID,
                    previousStatus: previousStatus,
                    currentStatus: session.status,
                    pid: session.pid
                )
            )
        }

        return reconciled
    }
}

public struct LoadRuntimeLogsUseCase: Sendable {
    private let sessions: any RunSessionRepository
    private let logReader: any RuntimeLogReader

    public init(sessions: any RunSessionRepository, logReader: any RuntimeLogReader) {
        self.sessions = sessions
        self.logReader = logReader
    }

    public func execute(sessionID: RunSession.ID, tail: Int, afterLine: Int? = nil) async throws -> RuntimeLogSnapshot? {
        guard let session = try await sessions.get(id: sessionID) else {
            return nil
        }

        let chunk: RuntimeLogChunk
        if let afterLine {
            chunk = try await logReader.readAfter(sessionID: sessionID, line: afterLine)
        } else {
            chunk = try await logReader.readRecent(sessionID: sessionID, tail: tail)
        }
        return RuntimeLogSnapshot(
            sessionID: session.id,
            projectID: session.projectID,
            runtimeProfileID: session.runtimeProfileID,
            status: session.status,
            pid: session.pid,
            lines: chunk.lines,
            nextLine: chunk.nextLine
        )
    }
}

public struct UpsertEnvSetUseCase: Sendable {
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore

    public init(envSets: any EnvSetRepository, secrets: any SecretsStore) {
        self.envSets = envSets
        self.secrets = secrets
    }

    public func execute(
        projectID: Project.ID,
        name: String,
        variables: [String: String],
        encrypted: Bool = true
    ) async throws -> EnvSet {
        let existing = try await envSets.list(projectID: projectID).first { $0.name == name }
        let envSet = EnvSet(
            id: existing?.id ?? UUID(),
            projectID: projectID,
            name: name,
            variables: encrypted ? [:] : variables,
            isEncrypted: encrypted,
            scope: existing?.scope ?? .project
        )

        try await envSets.save(envSet)
        if encrypted {
            try await secrets.save(values: variables, for: envSet.id)
        }
        return envSet
    }
}

public struct LoadEnvSetUseCase: Sendable {
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore

    public init(envSets: any EnvSetRepository, secrets: any SecretsStore) {
        self.envSets = envSets
        self.secrets = secrets
    }

    public func execute(projectID: Project.ID, name: String) async throws -> EnvSetSnapshot? {
        guard let envSet = try await envSets.list(projectID: projectID).first(where: { $0.name == name }) else {
            return nil
        }

        let variables: [String: String]
        if envSet.isEncrypted {
            variables = try await secrets.load(for: envSet.id)
        } else {
            variables = envSet.variables
        }

        return EnvSetSnapshot(envSet: envSet, resolvedVariables: variables)
    }
}

public struct ListDashboardSummaryUseCase: Sendable {
    private let projects: any ProjectRepository
    private let sessions: any RunSessionRepository

    public init(projects: any ProjectRepository, sessions: any RunSessionRepository) {
        self.projects = projects
        self.sessions = sessions
    }

    public func execute() async throws -> DashboardSummary {
        let projects = try await projects.list()
        var runningSessions = 0
        var failedSessions = 0

        for project in projects {
            let recent = try await sessions.list(projectID: project.id, limit: 10)
            runningSessions += recent.filter { $0.status == .running }.count
            failedSessions += recent.filter { $0.status == .failed }.count
        }

        return DashboardSummary(
            totalProjects: projects.count,
            activeProjects: projects.filter { $0.status == .active }.count,
            runningSessions: runningSessions,
            failedSessions: failedSessions
        )
    }
}
