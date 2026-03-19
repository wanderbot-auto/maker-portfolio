import Foundation
import Testing
import MakerAdapters
import MakerApplication
import MakerDomain
import MakerInfrastructure

@Test
func runtimeDaemonServerStartsReportsLogsAndStopsSession() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }

    let projects = InMemoryProjectRepository()
    let runtimeProfiles = InMemoryRuntimeProfileRepository()
    let envSets = InMemoryEnvSetRepository()
    let sessions = InMemoryRunSessionRepository()
    let milestones = InMemoryMilestoneRepository()
    let notes = InMemoryProjectNoteRepository()
    let scanner = FileSystemProjectScanner()
    let secrets = InMemorySecretsStore()
    let processInspector = SystemProcessInspector()
    let logStore = LogFileStore(logsDirectory: root.appendingPathComponent("logs", isDirectory: true))
    let runtimeManager = DefaultRuntimeManager(
        adapterFactory: DefaultRuntimeAdapterFactory(),
        sessions: sessions,
        envSets: envSets,
        secrets: secrets,
        logStore: logStore
    )
    let healthChecks = DefaultHealthCheckRunner(processInspector: processInspector)
    let services = CoreServices(
        projects: projects,
        runtimeProfiles: runtimeProfiles,
        envSets: envSets,
        runSessions: sessions,
        milestones: milestones,
        notes: notes,
        scanner: scanner,
        secrets: secrets,
        runtimeManager: runtimeManager,
        healthChecks: healthChecks,
        logStore: logStore,
        processInspector: processInspector,
        database: nil
    )

    let project = Project(name: "Maker", localPath: root.path, status: .active)
    let profile = RuntimeProfile(
        projectID: project.id,
        name: "daemon-test",
        entryCommand: "python3",
        workingDir: root.path,
        args: ["-u", "-c", "\"import time; print('ready', flush=True); time.sleep(2)\""]
    )
    try await projects.save(project)
    try await runtimeProfiles.save(profile)

    let token = "integration-token"
    let port = UInt16.random(in: 49152...59999)
    let server = RuntimeDaemonServer(services: services, authToken: token, port: port)
    try server.start()
    try await Task.sleep(for: .milliseconds(200))

    let client = DaemonClient(port: port)
    let ping = try await client.send(DaemonRequest(token: token, action: "ping"))
    #expect(ping.ok)
    #expect(ping.message == "pong")

    let started = try await client.send(
        DaemonRequest(
            token: token,
            action: "runtime.start",
            projectID: project.id.uuidString,
            runtimeProfileID: profile.id.uuidString
        )
    )
    #expect(started.ok)
    let sessionID = try #require(started.session?.sessionID)

    try await Task.sleep(for: .milliseconds(400))

    let status = try await client.send(
        DaemonRequest(
            token: token,
            action: "runtime.status",
            sessionID: sessionID
        )
    )
    #expect(status.ok)
    #expect(status.session?.status == "running")

    var logs = try await client.send(
        DaemonRequest(
            token: token,
            action: "runtime.logs",
            sessionID: sessionID,
            tail: 20
        )
    )
    for _ in 0..<5 where logs.logs.isEmpty {
        try await Task.sleep(for: .milliseconds(200))
        logs = try await client.send(
            DaemonRequest(
                token: token,
                action: "runtime.logs",
                sessionID: sessionID,
                tail: 20
            )
        )
    }
    #expect(logs.ok)
    #expect(logs.logs.contains { $0.contains("Started") || $0.contains("ready") })

    let stopped = try await client.send(
        DaemonRequest(
            token: token,
            action: "runtime.stop",
            sessionID: sessionID
        )
    )
    #expect(stopped.ok)

    let shutdown = try await client.send(DaemonRequest(token: token, action: "shutdown"))
    #expect(shutdown.ok)
}
