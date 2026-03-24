import Foundation
import MakerApplication
import MakerDomain
import MakerInfrastructure

@MainActor
final class WorkspaceDashboardStore: ObservableObject {
    @Published private(set) var snapshot = WorkspaceDashboardSnapshot.placeholder
    @Published private(set) var selectedProject: ProjectDetailPageModel?
    @Published private(set) var isLoading = false
    @Published private(set) var isProjectLoading = false
    @Published private(set) var isRunningAction = false
    @Published private(set) var isBuildAction = false
    @Published private(set) var loadError: String?

    private var services: CoreServices?
    private var projectItems: [Project.ID: ProjectListItem] = [:]
    private let commandRunner = WorkspaceLocalCommandRunner()
    private var latestBuilds: [Project.ID: CommandExecutionResult] = [:]
    private var actionFeedbacks: [Project.ID: ActionFeedback] = [:]

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let services = try CoreServices.makeDefault()
            self.services = services
            let summary = try await ListDashboardSummaryUseCase(
                projects: services.projects,
                sessions: services.runSessions
            ).execute()
            let projects = try await ListProjectsUseCase(
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                sessions: services.runSessions
            ).execute()

            if projects.isEmpty {
                snapshot = .placeholder
                loadError = nil
                return
            }

            projectItems = Dictionary(uniqueKeysWithValues: projects.map { ($0.project.id, $0) })
            snapshot = .live(summary: summary, projects: projects)
            loadError = nil

            if let selectedProjectID = selectedProject?.projectID {
                await selectProject(projectID: selectedProjectID)
            }
        } catch {
            snapshot = .placeholder
            selectedProject = nil
            loadError = error.localizedDescription
        }
    }

    func showOverview() {
        selectedProject = nil
    }

    func selectProject(projectID: Project.ID) async {
        guard let services else { return }
        guard projectItems[projectID] != nil else { return }

        isProjectLoading = true
        defer { isProjectLoading = false }

        do {
            selectedProject = try await makeProjectDetail(projectID: projectID, services: services)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    func refreshSelectedProject() async {
        guard let projectID = selectedProject?.projectID else {
            await load()
            return
        }
        await selectProject(projectID: projectID)
    }

    func buildSelectedProject() async {
        guard let selectedProject, let command = selectedProject.buildCommand else { return }

        isBuildAction = true
        defer { isBuildAction = false }

        do {
            let result = try await commandRunner.execute(command)
            latestBuilds[selectedProject.projectID] = result
            actionFeedbacks[selectedProject.projectID] = ActionFeedback(
                tone: result.succeeded ? .success : .failure,
                message: result.succeeded ? "Build completed successfully." : "Build finished with non-zero exit code.",
                timestamp: result.executedAt
            )
        } catch {
            actionFeedbacks[selectedProject.projectID] = ActionFeedback(
                tone: .failure,
                message: error.localizedDescription,
                timestamp: Date()
            )
        }

        await refreshSelectedProject()
    }

    func runSelectedProject() async {
        guard let selectedProject, let services else { return }

        isRunningAction = true
        defer { isRunningAction = false }

        do {
            let projectID = selectedProject.projectID
            var runtimeProfiles = try await ListRuntimeProfilesUseCase(runtimeProfiles: services.runtimeProfiles).execute(projectID: projectID)

            if runtimeProfiles.isEmpty {
                _ = try await RescanProjectUseCase(
                    projects: services.projects,
                    runtimeProfiles: services.runtimeProfiles,
                    scanner: services.scanner
                ).execute(projectID: projectID)
                runtimeProfiles = try await ListRuntimeProfilesUseCase(runtimeProfiles: services.runtimeProfiles).execute(projectID: projectID)
            }

            guard let profile = preferredRuntimeProfile(from: runtimeProfiles) else {
                actionFeedbacks[projectID] = ActionFeedback(
                    tone: .failure,
                    message: "No runnable profile found for this project.",
                    timestamp: Date()
                )
                await refreshSelectedProject()
                return
            }

            _ = try await StartRuntimeUseCase(
                projects: services.projects,
                runtimeProfiles: services.runtimeProfiles,
                runtimeManager: services.runtimeManager,
                sessions: services.runSessions,
                healthChecks: services.healthChecks
            ).execute(projectID: projectID, runtimeProfileID: profile.id)

            actionFeedbacks[projectID] = ActionFeedback(
                tone: .success,
                message: "Started \(profile.name).",
                timestamp: Date()
            )
        } catch {
            actionFeedbacks[selectedProject.projectID] = ActionFeedback(
                tone: .failure,
                message: error.localizedDescription,
                timestamp: Date()
            )
        }

        await refreshSelectedProject()
    }

    func stopSelectedProject() async {
        guard let selectedProject, let services, let sessionID = selectedProject.runningSessionID else { return }

        isRunningAction = true
        defer { isRunningAction = false }

        do {
            try await StopRuntimeUseCase(runtimeManager: services.runtimeManager).execute(sessionID: sessionID)
            actionFeedbacks[selectedProject.projectID] = ActionFeedback(
                tone: .info,
                message: "Stopped active runtime session.",
                timestamp: Date()
            )
        } catch {
            actionFeedbacks[selectedProject.projectID] = ActionFeedback(
                tone: .failure,
                message: error.localizedDescription,
                timestamp: Date()
            )
        }

        await refreshSelectedProject()
    }

    func clearSelectedBuildOutput() {
        guard let projectID = selectedProject?.projectID else { return }
        latestBuilds.removeValue(forKey: projectID)
        actionFeedbacks[projectID] = ActionFeedback(
            tone: .info,
            message: "Cleared latest build output view.",
            timestamp: Date()
        )
        if var detail = selectedProject {
            detail = ProjectDetailPageModel(
                projectID: detail.projectID,
                title: detail.title,
                path: detail.path,
                stackSummary: detail.stackSummary,
                status: detail.status,
                description: detail.description,
                readmeSnippet: detail.readmeSnippet,
                footprint: detail.footprint,
                codeComposition: detail.codeComposition,
                supplyChain: detail.supplyChain,
                git: detail.git,
                runtimeProfiles: detail.runtimeProfiles,
                recentSessions: detail.recentSessions,
                recentLogs: detail.recentLogs,
                buildCommand: detail.buildCommand,
                latestBuild: nil,
                actionFeedback: actionFeedbacks[projectID]
            )
            selectedProject = detail
        }
    }

    private func makeProjectDetail(projectID: Project.ID, services: CoreServices) async throws -> ProjectDetailPageModel {
        guard let item = projectItems[projectID] else {
            throw NSError(domain: "MakerDesktop", code: 404, userInfo: [NSLocalizedDescriptionKey: "Project not found"])
        }

        let detailSnapshot = try await GetProjectDetailUseCase(
            projects: services.projects,
            runtimeProfiles: services.runtimeProfiles,
            envSets: services.envSets,
            sessions: services.runSessions,
            milestones: services.milestones,
            notes: services.notes
        ).execute(projectID: projectID, recentSessionLimit: 12)

        guard let detailSnapshot else {
            throw NSError(domain: "MakerDesktop", code: 404, userInfo: [NSLocalizedDescriptionKey: "Project detail unavailable"])
        }

        let scanResult = try? await services.scanner.scan(at: detailSnapshot.project.localPath)
        let analysis = await WorkspaceRepositoryInspector().analyze(
            project: detailSnapshot.project,
            scan: scanResult,
            runtimeProfiles: detailSnapshot.runtimeProfiles
        )

        let latestSession = detailSnapshot.recentSessions.first
        let runtimeLogs: [String]
        if let latestSession,
           let logSnapshot = try? await LoadRuntimeLogsUseCase(
            sessions: services.runSessions,
            logReader: services.logStore
           ).execute(sessionID: latestSession.id, tail: 16) {
            runtimeLogs = logSnapshot.lines
        } else {
            runtimeLogs = []
        }

        return ProjectDetailPageModel(
            projectID: detailSnapshot.project.id,
            title: detailSnapshot.project.name,
            path: detailSnapshot.project.localPath,
            stackSummary: detailSnapshot.project.stackSummary,
            status: WorkspaceStatus(project: detailSnapshot.project, latestSession: item.latestSession),
            description: detailSnapshot.project.description,
            readmeSnippet: scanResult?.readmeSnippet,
            footprint: analysis.footprint,
            codeComposition: analysis.composition,
            supplyChain: analysis.supplyChain,
            git: analysis.git,
            runtimeProfiles: detailSnapshot.runtimeProfiles.map(runtimeProfileDisplay),
            recentSessions: detailSnapshot.recentSessions.map(runtimeSessionDisplay),
            recentLogs: runtimeLogs,
            buildCommand: analysis.buildCommand,
            latestBuild: latestBuilds[projectID],
            actionFeedback: actionFeedbacks[projectID]
        )
    }

    private func preferredRuntimeProfile(from profiles: [RuntimeProfile]) -> RuntimeProfile? {
        profiles.sorted { lhs, rhs in
            runtimeProfilePriority(lhs) < runtimeProfilePriority(rhs)
        }.first
    }

    private func runtimeProfileDisplay(_ profile: RuntimeProfile) -> RuntimeProfileDisplayModel {
        RuntimeProfileDisplayModel(
            id: profile.id,
            name: profile.name,
            command: ([profile.entryCommand] + profile.args).joined(separator: " "),
            healthCheck: profile.healthCheckType == .none ? "None" : "\(profile.healthCheckType.rawValue): \(profile.healthCheckTarget ?? "-")",
            autoRestart: profile.autoRestart,
            priority: runtimeProfilePriority(profile)
        )
    }

    private func runtimeSessionDisplay(_ session: RunSession) -> RuntimeSessionDisplayModel {
        RuntimeSessionDisplayModel(
            id: session.id,
            status: session.status,
            startedAt: session.startedAt.formatted(date: .abbreviated, time: .shortened),
            detail: session.failureReason ?? (session.lastHealthCheckDetail ?? "No issues reported"),
            pid: session.pid.map(String.init) ?? "-"
        )
    }

    private func runtimeProfilePriority(_ profile: RuntimeProfile) -> Int {
        let name = profile.name.lowercased()
        if name.contains("dev") || name.contains("start") || name.contains("swift-run") {
            return 0
        }
        if name.contains("web") || name.contains("api") || name.contains("worker") {
            return 1
        }
        return 2
    }
}
