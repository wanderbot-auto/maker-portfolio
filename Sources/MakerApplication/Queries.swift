import Foundation
import MakerDomain

public struct ProjectListItem: Sendable, Equatable, Codable {
    public var project: Project
    public var runtimeCount: Int
    public var latestSession: RunSession?

    public init(project: Project, runtimeCount: Int, latestSession: RunSession?) {
        self.project = project
        self.runtimeCount = runtimeCount
        self.latestSession = latestSession
    }
}

public struct ProjectDetailSnapshot: Sendable, Equatable, Codable {
    public var project: Project
    public var runtimeProfiles: [RuntimeProfile]
    public var envSets: [EnvSet]
    public var recentSessions: [RunSession]
    public var milestones: [Milestone]
    public var note: ProjectNote?

    public init(
        project: Project,
        runtimeProfiles: [RuntimeProfile],
        envSets: [EnvSet],
        recentSessions: [RunSession],
        milestones: [Milestone],
        note: ProjectNote?
    ) {
        self.project = project
        self.runtimeProfiles = runtimeProfiles
        self.envSets = envSets
        self.recentSessions = recentSessions
        self.milestones = milestones
        self.note = note
    }
}

public struct DashboardSummary: Sendable, Equatable, Codable {
    public var totalProjects: Int
    public var activeProjects: Int
    public var runningSessions: Int
    public var failedSessions: Int

    public init(totalProjects: Int, activeProjects: Int, runningSessions: Int, failedSessions: Int) {
        self.totalProjects = totalProjects
        self.activeProjects = activeProjects
        self.runningSessions = runningSessions
        self.failedSessions = failedSessions
    }
}

public struct ProjectRescanResult: Sendable, Equatable, Codable {
    public var project: Project
    public var createdProfiles: [RuntimeProfile]
    public var scanResult: ProjectScanResult

    public init(project: Project, createdProfiles: [RuntimeProfile], scanResult: ProjectScanResult) {
        self.project = project
        self.createdProfiles = createdProfiles
        self.scanResult = scanResult
    }
}

public struct EnvSetSnapshot: Sendable, Equatable, Codable {
    public var envSet: EnvSet
    public var resolvedVariables: [String: String]

    public init(envSet: EnvSet, resolvedVariables: [String: String]) {
        self.envSet = envSet
        self.resolvedVariables = resolvedVariables
    }
}

public struct RuntimeSessionSnapshot: Sendable, Equatable, Codable {
    public var sessionID: RunSession.ID
    public var projectID: Project.ID
    public var runtimeProfileID: RuntimeProfile.ID
    public var status: RunSessionStatus
    public var pid: Int32?

    public init(
        sessionID: RunSession.ID,
        projectID: Project.ID,
        runtimeProfileID: RuntimeProfile.ID,
        status: RunSessionStatus,
        pid: Int32?
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
    }
}

public struct RuntimeHistoryItem: Sendable, Equatable, Codable {
    public var sessionID: RunSession.ID
    public var projectID: Project.ID
    public var runtimeProfileID: RuntimeProfile.ID
    public var status: RunSessionStatus
    public var pid: Int32?
    public var startedAt: Date
    public var endedAt: Date?
    public var exitCode: Int32?

    public init(
        sessionID: RunSession.ID,
        projectID: Project.ID,
        runtimeProfileID: RuntimeProfile.ID,
        status: RunSessionStatus,
        pid: Int32?,
        startedAt: Date,
        endedAt: Date?,
        exitCode: Int32?
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.exitCode = exitCode
    }

    public init(session: RunSession) {
        self.init(
            sessionID: session.id,
            projectID: session.projectID,
            runtimeProfileID: session.runtimeProfileID,
            status: session.status,
            pid: session.pid,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            exitCode: session.exitCode
        )
    }
}

public struct RuntimeReconcileItem: Sendable, Equatable, Codable {
    public var sessionID: RunSession.ID
    public var projectID: Project.ID
    public var runtimeProfileID: RuntimeProfile.ID
    public var previousStatus: RunSessionStatus
    public var currentStatus: RunSessionStatus
    public var pid: Int32?

    public init(
        sessionID: RunSession.ID,
        projectID: Project.ID,
        runtimeProfileID: RuntimeProfile.ID,
        previousStatus: RunSessionStatus,
        currentStatus: RunSessionStatus,
        pid: Int32?
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.previousStatus = previousStatus
        self.currentStatus = currentStatus
        self.pid = pid
    }
}

public struct RuntimeSessionDiagnosticItem: Sendable, Equatable, Codable {
    public var sessionID: RunSession.ID
    public var projectID: Project.ID
    public var runtimeProfileID: RuntimeProfile.ID
    public var status: RunSessionStatus
    public var pid: Int32?
    public var processRunning: Bool

    public init(
        sessionID: RunSession.ID,
        projectID: Project.ID,
        runtimeProfileID: RuntimeProfile.ID,
        status: RunSessionStatus,
        pid: Int32?,
        processRunning: Bool
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
        self.processRunning = processRunning
    }
}

public struct RuntimeLogSnapshot: Sendable, Equatable, Codable {
    public var sessionID: RunSession.ID
    public var projectID: Project.ID
    public var runtimeProfileID: RuntimeProfile.ID
    public var status: RunSessionStatus?
    public var pid: Int32?
    public var lines: [String]
    public var nextLine: Int

    public init(
        sessionID: RunSession.ID,
        projectID: Project.ID,
        runtimeProfileID: RuntimeProfile.ID,
        status: RunSessionStatus?,
        pid: Int32?,
        lines: [String],
        nextLine: Int
    ) {
        self.sessionID = sessionID
        self.projectID = projectID
        self.runtimeProfileID = runtimeProfileID
        self.status = status
        self.pid = pid
        self.lines = lines
        self.nextLine = nextLine
    }
}
