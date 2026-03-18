import Foundation
import Testing
import MakerDomain
import MakerInfrastructure

@Test
func appPathsReservesSQLiteDatabaseLocation() {
    let paths = AppPaths()
    #expect(paths.databaseURL.lastPathComponent == "maker.sqlite")
    #expect(paths.logsDirectory.lastPathComponent == "Logs")
    #expect(paths.daemonLaunchAgentURL.lastPathComponent == "\(AppPaths.daemonLaunchAgentLabel).plist")
    #expect(paths.daemonStdoutURL.lastPathComponent == "daemon.stdout.log")
    #expect(paths.daemonStderrURL.lastPathComponent == "daemon.stderr.log")
}

@Test
func migratorBootstrapsSchemaIdempotently() async throws {
    let (database, directory) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(at: directory) }

    let migrator = DatabaseMigrator(database: database)
    try migrator.migrate()
    try migrator.migrate()

    let versionRows = try database.query("PRAGMA user_version;")
    let tableRows = try database.query(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('projects', 'runtime_profiles', 'env_sets', 'env_set_secrets', 'run_sessions', 'milestones', 'project_notes') ORDER BY name;"
    )

    #expect(versionRows.first?["user_version"]?.int64Value == 2)
    #expect(tableRows.count == 7)
}

@Test
func sqliteProjectRepositoryRoundTripsCoreFields() async throws {
    let (database, directory) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(at: directory) }

    try DatabaseMigrator(database: database).migrate()
    let repository = SQLiteProjectRepository(database: database)

    let project = Project(
        name: "Maker Portfolio",
        localPath: "/Users/wander/Documents/code/apps/maker-portfolio",
        repoType: .git,
        description: "Core workspace",
        status: .active,
        priority: .p1,
        tags: ["swift", "macos"],
        stackSummary: "Swift / SQLite"
    )

    try await repository.save(project)
    let stored = try await repository.get(id: project.id)

    #expect(stored?.id == project.id)
    #expect(stored?.name == project.name)
    #expect(stored?.slug == project.slug)
    #expect(stored?.localPath == project.localPath)
    #expect(stored?.repoType == project.repoType)
    #expect(stored?.status == project.status)
    #expect(stored?.priority == project.priority)
    #expect(stored?.tags == project.tags)
    #expect(stored?.stackSummary == project.stackSummary)
}

@Test
func sqliteRunSessionRepositoryOrdersNewestFirst() async throws {
    let (database, directory) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(at: directory) }

    try DatabaseMigrator(database: database).migrate()

    let projects = SQLiteProjectRepository(database: database)
    let profiles = SQLiteRuntimeProfileRepository(database: database)
    let sessions = SQLiteRunSessionRepository(database: database)

    let project = Project(name: "Order Test", localPath: "/tmp/order-test", repoType: .localOnly, status: .active)
    try await projects.save(project)

    let profile = RuntimeProfile(
        projectID: project.id,
        name: "dev",
        entryCommand: "swift",
        workingDir: project.localPath,
        args: ["run"]
    )
    try await profiles.save(profile)

    let earlier = RunSession(
        projectID: project.id,
        runtimeProfileID: profile.id,
        status: .stopped,
        pid: 1001,
        startedAt: Date(timeIntervalSince1970: 1_000),
        endedAt: Date(timeIntervalSince1970: 1_020),
        exitCode: 0,
        triggerSource: .manual
    )
    let latest = RunSession(
        projectID: project.id,
        runtimeProfileID: profile.id,
        status: .running,
        pid: 1002,
        startedAt: Date(timeIntervalSince1970: 2_000),
        triggerSource: .automation
    )
    let middle = RunSession(
        projectID: project.id,
        runtimeProfileID: profile.id,
        status: .failed,
        pid: 1003,
        startedAt: Date(timeIntervalSince1970: 1_500),
        endedAt: Date(timeIntervalSince1970: 1_530),
        exitCode: 1,
        triggerSource: .recovery
    )

    try await sessions.save(earlier)
    try await sessions.save(latest)
    try await sessions.save(middle)

    let ordered = try await sessions.list(projectID: project.id, limit: 10)
    #expect(ordered.map(\.id) == [latest.id, middle.id, earlier.id])
    #expect(ordered.first?.status == .running)
}

@Test
func encryptedSQLiteSecretsStoreRoundTripsAndDeletesCiphertext() async throws {
    let (database, directory) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(at: directory) }

    try DatabaseMigrator(database: database).migrate()
    let projects = SQLiteProjectRepository(database: database)
    let envSets = SQLiteEnvSetRepository(database: database)

    let project = Project(name: "Secrets", localPath: "/tmp/secrets", repoType: .localOnly, status: .active)
    try await projects.save(project)

    let envSet = EnvSet(projectID: project.id, name: "local", variables: [:], isEncrypted: true)
    try await envSets.save(envSet)

    let store = EncryptedSQLiteSecretsStore(
        database: database,
        masterKeyProvider: FileSystemMasterKeyProvider(keyURL: directory.appendingPathComponent("master.key"))
    )

    try await store.save(values: ["API_TOKEN": "secret-value", "BASE_URL": "http://localhost"], for: envSet.id)
    let loaded = try await store.load(for: envSet.id)
    #expect(loaded["API_TOKEN"] == "secret-value")
    #expect(loaded["BASE_URL"] == "http://localhost")

    let rows = try database.query("SELECT encrypted_blob FROM env_set_secrets WHERE env_set_id = ?;", bindings: [.text(envSet.id.uuidString)])
    #expect(rows.count == 1)
    #expect(rows.first?["encrypted_blob"] != nil)

    try await store.delete(for: envSet.id)
    let deleted = try await store.load(for: envSet.id)
    #expect(deleted.isEmpty)
}

private func makeTemporaryDatabase() throws -> (SQLiteDatabase, URL) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let database = try SQLiteDatabase(path: directory.appendingPathComponent("maker.sqlite").path)
    return (database, directory)
}
