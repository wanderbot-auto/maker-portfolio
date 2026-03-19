import Foundation
import MakerAdapters
import MakerApplication
import MakerDomain

public struct CoreServices {
    public let projects: any ProjectRepository
    public let runtimeProfiles: any RuntimeProfileRepository
    public let envSets: any EnvSetRepository
    public let runSessions: any RunSessionRepository
    public let milestones: any MilestoneRepository
    public let notes: any ProjectNoteRepository
    public let scanner: FileSystemProjectScanner
    public let secrets: any SecretsStore
    public let runtimeManager: any RuntimeManager
    public let healthChecks: any HealthCheckRunner
    public let logStore: LogFileStore
    public let processInspector: any ProcessInspector
    public let database: SQLiteDatabase?

    public init(
        projects: any ProjectRepository,
        runtimeProfiles: any RuntimeProfileRepository,
        envSets: any EnvSetRepository,
        runSessions: any RunSessionRepository,
        milestones: any MilestoneRepository,
        notes: any ProjectNoteRepository,
        scanner: FileSystemProjectScanner,
        secrets: any SecretsStore,
        runtimeManager: any RuntimeManager,
        healthChecks: any HealthCheckRunner,
        logStore: LogFileStore,
        processInspector: any ProcessInspector,
        database: SQLiteDatabase? = nil
    ) {
        self.projects = projects
        self.runtimeProfiles = runtimeProfiles
        self.envSets = envSets
        self.runSessions = runSessions
        self.milestones = milestones
        self.notes = notes
        self.scanner = scanner
        self.secrets = secrets
        self.runtimeManager = runtimeManager
        self.healthChecks = healthChecks
        self.logStore = logStore
        self.processInspector = processInspector
        self.database = database
    }

    public static func makeDefault() throws -> CoreServices {
        let paths = AppPaths()
        try paths.createIfNeeded()

        let database = try SQLiteDatabase(path: paths.databaseURL.path)
        let migrator = DatabaseMigrator(database: database)
        try migrator.migrate()

        let projects = SQLiteProjectRepository(database: database)
        let runtimeProfiles = SQLiteRuntimeProfileRepository(database: database)
        let envSets = SQLiteEnvSetRepository(database: database)
        let runSessions = SQLiteRunSessionRepository(database: database)
        let milestones = SQLiteMilestoneRepository(database: database)
        let notes = SQLiteProjectNoteRepository(database: database)
        let scanner = FileSystemProjectScanner()
        let secrets = EncryptedSQLiteSecretsStore(
            database: database,
            masterKeyProvider: FileSystemMasterKeyProvider(keyURL: paths.masterKeyURL)
        )
        let logStore = LogFileStore(logsDirectory: paths.logsDirectory)
        let processInspector = SystemProcessInspector()
        let healthChecks = DefaultHealthCheckRunner(processInspector: processInspector)
        let runtimeManager = DefaultRuntimeManager(
            adapterFactory: DefaultRuntimeAdapterFactory(),
            sessions: runSessions,
            envSets: envSets,
            secrets: secrets,
            logStore: logStore
        )

        return CoreServices(
            projects: projects,
            runtimeProfiles: runtimeProfiles,
            envSets: envSets,
            runSessions: runSessions,
            milestones: milestones,
            notes: notes,
            scanner: scanner,
            secrets: secrets,
            runtimeManager: runtimeManager,
            healthChecks: healthChecks,
            logStore: logStore,
            processInspector: processInspector,
            database: database
        )
    }

    public static func makeInMemoryPreview() throws -> CoreServices {
        let projects = InMemoryProjectRepository()
        let runtimeProfiles = InMemoryRuntimeProfileRepository()
        let envSets = InMemoryEnvSetRepository()
        let runSessions = InMemoryRunSessionRepository()
        let milestones = InMemoryMilestoneRepository()
        let notes = InMemoryProjectNoteRepository()
        let scanner = FileSystemProjectScanner()
        let secrets = InMemorySecretsStore()
        let paths = AppPaths()
        try paths.createIfNeeded()
        let logStore = LogFileStore(logsDirectory: paths.logsDirectory)
        let processInspector = SystemProcessInspector()
        let healthChecks = DefaultHealthCheckRunner(processInspector: processInspector)
        let runtimeManager = DefaultRuntimeManager(
            adapterFactory: DefaultRuntimeAdapterFactory(),
            sessions: runSessions,
            envSets: envSets,
            secrets: secrets,
            logStore: logStore
        )

        return CoreServices(
            projects: projects,
            runtimeProfiles: runtimeProfiles,
            envSets: envSets,
            runSessions: runSessions,
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
    }
}
