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

    public func execute(
        status: ProjectStatus? = nil,
        tag: String? = nil,
        query: String? = nil
    ) async throws -> [ProjectListItem] {
        let filteredProjects = try await projects.list().filter { project in
            if let status, project.status != status {
                return false
            }
            if let tag, !tag.isEmpty, project.tags.contains(tag) == false {
                return false
            }
            if let query, !query.isEmpty, matches(project: project, query: query) == false {
                return false
            }
            return true
        }
        var items: [ProjectListItem] = []

        for project in filteredProjects {
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

    private func matches(project: Project, query: String) -> Bool {
        let needle = query.lowercased()
        let fields = [
            project.name,
            project.slug,
            project.localPath,
            project.description,
            project.stackSummary
        ] + project.tags
        return fields.contains { $0.lowercased().contains(needle) }
    }
}

public struct GetProjectDetailUseCase: Sendable {
    private let projects: any ProjectRepository
    private let runtimeProfiles: any RuntimeProfileRepository
    private let envSets: any EnvSetRepository
    private let sessions: any RunSessionRepository
    private let milestones: any MilestoneRepository
    private let notes: any ProjectNoteRepository

    public init(
        projects: any ProjectRepository,
        runtimeProfiles: any RuntimeProfileRepository,
        envSets: any EnvSetRepository,
        sessions: any RunSessionRepository,
        milestones: any MilestoneRepository,
        notes: any ProjectNoteRepository
    ) {
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.envSets = envSets
        self.sessions = sessions
        self.milestones = milestones
        self.notes = notes
    }

    public func execute(projectID: Project.ID, recentSessionLimit: Int = 10) async throws -> ProjectDetailSnapshot? {
        guard let project = try await projects.get(id: projectID) else {
            return nil
        }

        async let runtimeProfilesTask = runtimeProfiles.list(projectID: projectID)
        async let envSetsTask = envSets.list(projectID: projectID)
        async let sessionsTask = sessions.list(projectID: projectID, limit: recentSessionLimit)
        async let milestonesTask = milestones.list(projectID: projectID)
        async let noteTask = notes.get(projectID: projectID)

        let loadedRuntimeProfiles = try await runtimeProfilesTask
        let loadedEnvSets = try await envSetsTask
        let loadedSessions = try await sessionsTask
        let loadedMilestones = try await milestonesTask
        let loadedNote = try await noteTask

        return ProjectDetailSnapshot(
            project: project,
            runtimeProfiles: loadedRuntimeProfiles,
            envSets: loadedEnvSets,
            recentSessions: loadedSessions,
            milestones: loadedMilestones,
            note: loadedNote
        )
    }
}

public struct UpdateProjectUseCase: Sendable {
    private let projects: any ProjectRepository

    public init(projects: any ProjectRepository) {
        self.projects = projects
    }

    public func execute(
        projectID: Project.ID,
        name: String? = nil,
        description: String? = nil,
        status: ProjectStatus? = nil,
        priority: ProjectPriority? = nil
    ) async throws -> Project {
        guard var project = try await projects.get(id: projectID) else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }

        if let name, !name.isEmpty {
            project.name = name
            project.slug = Project.makeSlug(from: name)
        }
        if let description {
            project.description = description
        }
        if let status {
            project.status = status
            if status == .archived {
                project.archivedAt = project.archivedAt ?? Date()
            } else {
                project.archivedAt = nil
            }
        }
        if let priority {
            project.priority = priority
        }
        project.updatedAt = Date()

        try await projects.save(project)
        return project
    }
}

public struct ArchiveProjectUseCase: Sendable {
    private let projects: any ProjectRepository

    public init(projects: any ProjectRepository) {
        self.projects = projects
    }

    public func execute(projectID: Project.ID) async throws -> Project {
        try await projects.archive(id: projectID, at: Date())
        guard let project = try await projects.get(id: projectID) else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }
        return project
    }
}

public struct DeleteProjectUseCase: Sendable {
    private let projects: any ProjectRepository

    public init(projects: any ProjectRepository) {
        self.projects = projects
    }

    public func execute(projectID: Project.ID) async throws {
        guard try await projects.get(id: projectID) != nil else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }
        try await projects.delete(id: projectID)
    }
}

public struct UnarchiveProjectUseCase: Sendable {
    private let projects: any ProjectRepository

    public init(projects: any ProjectRepository) {
        self.projects = projects
    }

    public func execute(projectID: Project.ID, restoredStatus: ProjectStatus = .active) async throws -> Project {
        guard var project = try await projects.get(id: projectID) else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }

        project.status = restoredStatus
        project.archivedAt = nil
        project.updatedAt = Date()
        try await projects.save(project)
        return project
    }
}

public struct RescanProjectUseCase: Sendable {
    private let projects: any ProjectRepository
    private let runtimeProfiles: any RuntimeProfileRepository
    private let scanner: any ProjectScanner

    public init(
        projects: any ProjectRepository,
        runtimeProfiles: any RuntimeProfileRepository,
        scanner: any ProjectScanner
    ) {
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.scanner = scanner
    }

    public func execute(projectID: Project.ID) async throws -> ProjectRescanResult {
        guard var project = try await projects.get(id: projectID) else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }

        let scanResult = try await scanner.scan(at: project.localPath)
        project.repoType = scanResult.repoType
        project.stackSummary = scanResult.stackSummary
        project.updatedAt = Date()
        try await projects.save(project)

        let existingProfiles = try await runtimeProfiles.list(projectID: projectID)
        var createdProfiles: [RuntimeProfile] = []

        for discovered in scanResult.discoveredProfiles {
            let alreadyExists = existingProfiles.contains {
                $0.name == discovered.name &&
                    $0.entryCommand == discovered.entryCommand &&
                    $0.workingDir == discovered.workingDir &&
                    $0.args == discovered.args
            }
            guard alreadyExists == false else {
                continue
            }

            let profile = RuntimeProfile(
                projectID: projectID,
                name: discovered.name,
                entryCommand: discovered.entryCommand,
                workingDir: discovered.workingDir,
                args: discovered.args
            )
            try await runtimeProfiles.save(profile)
            createdProfiles.append(profile)
        }

        return ProjectRescanResult(project: project, createdProfiles: createdProfiles, scanResult: scanResult)
    }
}

public struct ImportProjectsUseCase: Sendable {
    private let projects: any ProjectRepository
    private let scanner: any ProjectScanner
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(
        projects: any ProjectRepository,
        scanner: any ProjectScanner,
        runtimeProfiles: any RuntimeProfileRepository
    ) {
        self.projects = projects
        self.scanner = scanner
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(
        paths: [String],
        tags: [String] = [],
        status: ProjectStatus = .idea,
        priority: ProjectPriority = .p2
    ) async throws -> ProjectImportResult {
        let uniquePaths = Array(Set(paths)).sorted()
        let existingPaths = Set(try await projects.list().map(\.localPath))
        var imported: [ProjectImportItem] = []
        var skippedPaths: [String] = []

        for path in uniquePaths {
            guard existingPaths.contains(path) == false else {
                skippedPaths.append(path)
                continue
            }

            let scanResult = try await scanner.scan(at: path)
            let project = Project(
                name: scanResult.suggestedName,
                localPath: path,
                repoType: scanResult.repoType,
                status: status,
                priority: priority,
                tags: tags,
                stackSummary: scanResult.stackSummary
            )
            try await projects.save(project)

            var profiles: [RuntimeProfile] = []
            for discovered in scanResult.discoveredProfiles {
                let profile = RuntimeProfile(
                    projectID: project.id,
                    name: discovered.name,
                    entryCommand: discovered.entryCommand,
                    workingDir: discovered.workingDir,
                    args: discovered.args
                )
                try await runtimeProfiles.save(profile)
                profiles.append(profile)
            }

            imported.append(ProjectImportItem(path: path, project: project, runtimeProfiles: profiles))
        }

        return ProjectImportResult(imported: imported, skippedPaths: skippedPaths)
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

public struct GetRuntimeProfileUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(profileID: RuntimeProfile.ID) async throws -> RuntimeProfile? {
        try await runtimeProfiles.get(id: profileID)
    }
}

public struct CreateRuntimeProfileUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(
        projectID: Project.ID,
        name: String,
        entryCommand: String,
        workingDir: String,
        args: [String] = []
    ) async throws -> RuntimeProfile {
        let profile = RuntimeProfile(
            projectID: projectID,
            name: name,
            entryCommand: entryCommand,
            workingDir: workingDir,
            args: args
        )
        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct UpdateRuntimeProfileUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(
        profileID: RuntimeProfile.ID,
        name: String? = nil,
        entryCommand: String? = nil,
        workingDir: String? = nil,
        args: [String]? = nil
    ) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }

        if let name, !name.isEmpty {
            profile.name = name
        }
        if let entryCommand, !entryCommand.isEmpty {
            profile.entryCommand = entryCommand
        }
        if let workingDir, !workingDir.isEmpty {
            profile.workingDir = workingDir
        }
        if let args {
            profile.args = args
        }

        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct DeleteRuntimeProfileUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(profileID: RuntimeProfile.ID) async throws {
        try await runtimeProfiles.delete(id: profileID)
    }
}

public struct AttachEnvSetToRuntimeProfileUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository
    private let envSets: any EnvSetRepository

    public init(runtimeProfiles: any RuntimeProfileRepository, envSets: any EnvSetRepository) {
        self.runtimeProfiles = runtimeProfiles
        self.envSets = envSets
    }

    public func execute(profileID: RuntimeProfile.ID, envSetID: EnvSet.ID) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }
        guard let envSet = try await envSets.get(id: envSetID) else {
            throw MakerError.missingResource("Env set \(envSetID.uuidString) not found")
        }
        guard envSet.projectID == profile.projectID else {
            throw MakerError.invalidConfiguration("Env set and runtime profile must belong to the same project.")
        }

        profile.envSetID = envSetID
        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct DetachEnvSetFromRuntimeProfileUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(profileID: RuntimeProfile.ID) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }

        profile.envSetID = nil
        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct AddRuntimeProfileDependencyUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(profileID: RuntimeProfile.ID, dependsOnProfileID: RuntimeProfile.ID) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }
        guard let dependency = try await runtimeProfiles.get(id: dependsOnProfileID) else {
            throw MakerError.missingResource("Runtime profile \(dependsOnProfileID.uuidString) not found")
        }
        guard profile.id != dependency.id else {
            throw MakerError.invalidConfiguration("Runtime profile cannot depend on itself.")
        }
        guard profile.projectID == dependency.projectID else {
            throw MakerError.invalidConfiguration("Dependencies must belong to the same project.")
        }

        if profile.dependsOn.contains(dependsOnProfileID) == false {
            profile.dependsOn.append(dependsOnProfileID)
            try await runtimeProfiles.save(profile)
        }
        return profile
    }
}

public struct RemoveRuntimeProfileDependencyUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(profileID: RuntimeProfile.ID, dependsOnProfileID: RuntimeProfile.ID) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }

        profile.dependsOn.removeAll { $0 == dependsOnProfileID }
        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct SetRuntimeProfileHealthCheckUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(
        profileID: RuntimeProfile.ID,
        type: HealthCheckType,
        target: String?
    ) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }

        if type == .none {
            profile.healthCheckType = .none
            profile.healthCheckTarget = nil
        } else {
            guard let target, !target.isEmpty else {
                throw MakerError.invalidConfiguration("Health check target is required for \(type.rawValue).")
            }
            profile.healthCheckType = type
            profile.healthCheckTarget = target
        }

        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct SetRuntimeProfileAutoRestartUseCase: Sendable {
    private let runtimeProfiles: any RuntimeProfileRepository

    public init(runtimeProfiles: any RuntimeProfileRepository) {
        self.runtimeProfiles = runtimeProfiles
    }

    public func execute(profileID: RuntimeProfile.ID, enabled: Bool) async throws -> RuntimeProfile {
        guard var profile = try await runtimeProfiles.get(id: profileID) else {
            throw MakerError.missingResource("Runtime profile \(profileID.uuidString) not found")
        }

        profile.autoRestart = enabled
        try await runtimeProfiles.save(profile)
        return profile
    }
}

public struct StartRuntimeUseCase: Sendable {
    private let projects: any ProjectRepository
    private let runtimeProfiles: any RuntimeProfileRepository
    private let runtimeManager: any RuntimeManager
    private let sessions: any RunSessionRepository
    private let healthChecks: any HealthCheckRunner

    public init(
        projects: any ProjectRepository,
        runtimeProfiles: any RuntimeProfileRepository,
        runtimeManager: any RuntimeManager,
        sessions: any RunSessionRepository,
        healthChecks: any HealthCheckRunner
    ) {
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.runtimeManager = runtimeManager
        self.sessions = sessions
        self.healthChecks = healthChecks
    }

    public func execute(projectID: Project.ID, runtimeProfileID: RuntimeProfile.ID) async throws -> RunSession {
        guard let project = try await projects.get(id: projectID) else {
            throw NSError(domain: "MakerApplication.StartRuntimeUseCase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Project not found"])
        }
        guard let profile = try await runtimeProfiles.get(id: runtimeProfileID) else {
            throw NSError(domain: "MakerApplication.StartRuntimeUseCase", code: 404, userInfo: [NSLocalizedDescriptionKey: "Runtime profile not found"])
        }
        return try await ensureRunning(project: project, profile: profile, stack: [])
    }

    private func ensureRunning(
        project: Project,
        profile: RuntimeProfile,
        stack: [RuntimeProfile.ID]
    ) async throws -> RunSession {
        if stack.contains(profile.id) {
            throw MakerError.invalidConfiguration("Runtime dependency cycle detected.")
        }

        for dependencyID in profile.dependsOn {
            guard let dependency = try await runtimeProfiles.get(id: dependencyID) else {
                throw MakerError.missingResource("Runtime profile \(dependencyID.uuidString) not found")
            }
            _ = try await ensureRunning(project: project, profile: dependency, stack: stack + [profile.id])
        }

        if let running = try await sessions.listRunning().first(where: {
            $0.projectID == project.id && $0.runtimeProfileID == profile.id
        }) {
            return running
        }

        let maximumAttempts = profile.autoRestart ? 3 : 1
        var lastError: Error?

        for _ in 0..<maximumAttempts {
            let session = try await runtimeManager.start(project: project, profile: profile)
            do {
                return try await waitForHealthIfNeeded(session: session, profile: profile)
            } catch {
                lastError = error
                try? await runtimeManager.stop(sessionID: session.id)
            }
        }

        throw lastError ?? MakerError.invalidConfiguration("Unable to start runtime profile \(profile.name).")
    }

    private func waitForHealthIfNeeded(session: RunSession, profile: RuntimeProfile) async throws -> RunSession {
        guard profile.healthCheckType != .none else {
            return session
        }

        let deadline = Date().addingTimeInterval(8)
        var latestSession = session

        while Date() < deadline {
            guard let reloaded = try await sessions.get(id: session.id) else {
                throw MakerError.missingResource("Run session \(session.id.uuidString) not found")
            }
            latestSession = reloaded

            let result = await healthChecks.evaluate(profile: profile, session: latestSession)
            latestSession = try await recordHealth(session: latestSession, result: result)
            if result.status == .passing {
                return latestSession
            }

            try await Task.sleep(for: .milliseconds(400))
        }

        latestSession.status = .failed
        latestSession.failureReason = "health check timeout"
        latestSession.endedAt = Date()
        try await sessions.update(latestSession)
        throw MakerError.invalidConfiguration("Health check timed out for runtime profile \(profile.name).")
    }

    private func recordHealth(session: RunSession, result: HealthCheckResult) async throws -> RunSession {
        var updated = session
        updated.lastHealthCheckStatus = result.status
        updated.lastHealthCheckDetail = result.detail
        updated.lastHealthCheckAt = result.checkedAt
        if result.status == .passing {
            updated.failureReason = nil
        }
        try await sessions.update(updated)
        return updated
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
    private let healthChecks: (any HealthCheckRunner)?

    public init(
        runtimeManager: any RuntimeManager,
        projects: (any ProjectRepository)? = nil,
        runtimeProfiles: (any RuntimeProfileRepository)? = nil,
        sessions: (any RunSessionRepository)? = nil,
        healthChecks: (any HealthCheckRunner)? = nil
    ) {
        self.runtimeManager = runtimeManager
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.sessions = sessions
        self.healthChecks = healthChecks
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
                let healthChecks,
                let previousSession = try await sessions.get(id: sessionID),
                let project = try await projects.get(id: previousSession.projectID),
                let profile = try await runtimeProfiles.get(id: previousSession.runtimeProfileID)
            else {
                throw error
            }

            return try await StartRuntimeUseCase(
                projects: projects,
                runtimeProfiles: runtimeProfiles,
                runtimeManager: runtimeManager,
                sessions: sessions,
                healthChecks: healthChecks
            ).execute(projectID: project.id, runtimeProfileID: profile.id)
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

public struct ListRuntimeSessionsUseCase: Sendable {
    private let sessions: any RunSessionRepository

    public init(sessions: any RunSessionRepository) {
        self.sessions = sessions
    }

    public func execute(
        projectID: Project.ID? = nil,
        status: RunSessionStatus? = nil,
        limit: Int = 20
    ) async throws -> [RunSession] {
        let safeLimit = max(1, limit)
        if let projectID {
            let projectSessions = try await sessions.list(projectID: projectID, limit: safeLimit)
            if let status {
                return projectSessions.filter { $0.status == status }
            }
            return projectSessions
        }
        return try await sessions.listAll(limit: safeLimit, status: status)
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

public struct DiagnoseRuntimeSessionsUseCase: Sendable {
    private let sessions: any RunSessionRepository
    private let processInspector: any ProcessInspector

    public init(sessions: any RunSessionRepository, processInspector: any ProcessInspector) {
        self.sessions = sessions
        self.processInspector = processInspector
    }

    public func execute() async throws -> [RuntimeSessionDiagnosticItem] {
        let recentSessions = try await sessions.listAll(limit: 50, status: nil)
        var items: [RuntimeSessionDiagnosticItem] = []

        for session in recentSessions where session.status == .running || session.failureReason != nil {
            let processRunning: Bool
            if let pid = session.pid {
                processRunning = await processInspector.isProcessRunning(pid: pid)
            } else {
                processRunning = false
            }

            items.append(
                RuntimeSessionDiagnosticItem(
                    sessionID: session.id,
                    projectID: session.projectID,
                    runtimeProfileID: session.runtimeProfileID,
                    status: session.status,
                    pid: session.pid,
                    processRunning: processRunning,
                    restartCount: session.restartCount,
                    failureReason: session.failureReason,
                    lastHealthCheckStatus: session.lastHealthCheckStatus,
                    lastHealthCheckDetail: session.lastHealthCheckDetail,
                    lastHealthCheckAt: session.lastHealthCheckAt
                )
            )
        }

        return items
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

public struct ListEnvSetsUseCase: Sendable {
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore

    public init(envSets: any EnvSetRepository, secrets: any SecretsStore) {
        self.envSets = envSets
        self.secrets = secrets
    }

    public func execute(projectID: Project.ID) async throws -> [EnvSetSnapshot] {
        let sets = try await envSets.list(projectID: projectID)
        var snapshots: [EnvSetSnapshot] = []

        for envSet in sets {
            let variables: [String: String]
            if envSet.isEncrypted {
                variables = try await secrets.load(for: envSet.id)
            } else {
                variables = envSet.variables
            }
            snapshots.append(EnvSetSnapshot(envSet: envSet, resolvedVariables: variables))
        }

        return snapshots
    }
}

public struct DeleteEnvSetUseCase: Sendable {
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore

    public init(envSets: any EnvSetRepository, secrets: any SecretsStore) {
        self.envSets = envSets
        self.secrets = secrets
    }

    public func execute(projectID: Project.ID, name: String) async throws -> EnvSet? {
        guard let envSet = try await envSets.list(projectID: projectID).first(where: { $0.name == name }) else {
            return nil
        }

        try await envSets.delete(id: envSet.id)
        try await secrets.delete(for: envSet.id)
        return envSet
    }
}

public struct UnsetEnvVariablesUseCase: Sendable {
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore

    public init(envSets: any EnvSetRepository, secrets: any SecretsStore) {
        self.envSets = envSets
        self.secrets = secrets
    }

    public func execute(projectID: Project.ID, name: String, keys: [String]) async throws -> EnvSetSnapshot? {
        guard var envSet = try await envSets.list(projectID: projectID).first(where: { $0.name == name }) else {
            return nil
        }

        let normalizedKeys = Set(keys)
        var values = envSet.isEncrypted ? try await secrets.load(for: envSet.id) : envSet.variables
        for key in normalizedKeys {
            values.removeValue(forKey: key)
        }

        if envSet.isEncrypted {
            if values.isEmpty {
                try await secrets.delete(for: envSet.id)
            } else {
                try await secrets.save(values: values, for: envSet.id)
            }
        } else {
            envSet.variables = values
            try await envSets.save(envSet)
        }

        return EnvSetSnapshot(envSet: envSet, resolvedVariables: values)
    }
}

public struct CopyEnvSetUseCase: Sendable {
    private let envSets: any EnvSetRepository
    private let secrets: any SecretsStore

    public init(envSets: any EnvSetRepository, secrets: any SecretsStore) {
        self.envSets = envSets
        self.secrets = secrets
    }

    public func execute(projectID: Project.ID, sourceName: String, targetName: String) async throws -> EnvSetSnapshot? {
        guard let source = try await envSets.list(projectID: projectID).first(where: { $0.name == sourceName }) else {
            return nil
        }

        let variables: [String: String]
        if source.isEncrypted {
            variables = try await secrets.load(for: source.id)
        } else {
            variables = source.variables
        }

        let copied = try await UpsertEnvSetUseCase(envSets: envSets, secrets: secrets).execute(
            projectID: projectID,
            name: targetName,
            variables: variables,
            encrypted: source.isEncrypted
        )
        return EnvSetSnapshot(envSet: copied, resolvedVariables: variables)
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

public struct ListMilestonesUseCase: Sendable {
    private let projects: any ProjectRepository
    private let milestones: any MilestoneRepository

    public init(projects: any ProjectRepository, milestones: any MilestoneRepository) {
        self.projects = projects
        self.milestones = milestones
    }

    public func execute(projectID: Project.ID) async throws -> [Milestone] {
        guard try await projects.get(id: projectID) != nil else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }
        return try await milestones.list(projectID: projectID)
    }
}

public struct CreateMilestoneUseCase: Sendable {
    private let projects: any ProjectRepository
    private let milestones: any MilestoneRepository

    public init(projects: any ProjectRepository, milestones: any MilestoneRepository) {
        self.projects = projects
        self.milestones = milestones
    }

    public func execute(projectID: Project.ID, title: String, dueDate: Date? = nil) async throws -> Milestone {
        guard try await projects.get(id: projectID) != nil else {
            throw MakerError.missingResource("Project \(projectID.uuidString) not found")
        }

        let milestone = Milestone(projectID: projectID, title: title, dueDate: dueDate)
        try await milestones.save(milestone)
        return milestone
    }
}

public struct UpdateMilestoneStateUseCase: Sendable {
    private let milestones: any MilestoneRepository

    public init(milestones: any MilestoneRepository) {
        self.milestones = milestones
    }

    public func execute(milestoneID: Milestone.ID, state: Milestone.State) async throws -> Milestone {
        guard var milestone = try await milestones.get(id: milestoneID) else {
            throw MakerError.missingResource("Milestone \(milestoneID.uuidString) not found")
        }

        milestone.state = state
        try await milestones.save(milestone)
        return milestone
    }
}

public struct UpdateMilestoneUseCase: Sendable {
    private let milestones: any MilestoneRepository

    public init(milestones: any MilestoneRepository) {
        self.milestones = milestones
    }

    public func execute(
        milestoneID: Milestone.ID,
        title: String? = nil,
        dueDate: Date?? = nil
    ) async throws -> Milestone {
        guard var milestone = try await milestones.get(id: milestoneID) else {
            throw MakerError.missingResource("Milestone \(milestoneID.uuidString) not found")
        }

        if let title {
            milestone.title = title
        }
        if let dueDate {
            milestone.dueDate = dueDate
        }

        try await milestones.save(milestone)
        return milestone
    }
}

public struct DeleteMilestoneUseCase: Sendable {
    private let milestones: any MilestoneRepository

    public init(milestones: any MilestoneRepository) {
        self.milestones = milestones
    }

    public func execute(milestoneID: Milestone.ID) async throws {
        guard try await milestones.get(id: milestoneID) != nil else {
            throw MakerError.missingResource("Milestone \(milestoneID.uuidString) not found")
        }
        try await milestones.delete(id: milestoneID)
    }
}

public struct LoadProjectNoteUseCase: Sendable {
    private let notes: any ProjectNoteRepository

    public init(notes: any ProjectNoteRepository) {
        self.notes = notes
    }

    public func execute(projectID: Project.ID) async throws -> ProjectNote? {
        try await notes.get(projectID: projectID)
    }
}

public struct SaveProjectNoteUseCase: Sendable {
    private let notes: any ProjectNoteRepository

    public init(notes: any ProjectNoteRepository) {
        self.notes = notes
    }

    public func execute(projectID: Project.ID, content: String) async throws -> ProjectNote {
        let note = ProjectNote(
            id: (try await notes.get(projectID: projectID))?.id ?? UUID(),
            projectID: projectID,
            content: content,
            updatedAt: Date()
        )
        try await notes.save(note)
        return note
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
