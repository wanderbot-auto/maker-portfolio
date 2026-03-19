import Foundation
import MakerApplication
import MakerDomain

public actor InMemoryProjectRepository: ProjectRepository {
    private var storage: [Project.ID: Project] = [:]

    public init() {}

    public func list() async throws -> [Project] {
        storage.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func get(id: Project.ID) async throws -> Project? {
        storage[id]
    }

    public func save(_ project: Project) async throws {
        storage[project.id] = project
    }

    public func archive(id: Project.ID, at: Date) async throws {
        guard var project = storage[id] else { return }
        project.status = .archived
        project.archivedAt = at
        project.updatedAt = at
        storage[id] = project
    }

    public func delete(id: Project.ID) async throws {
        storage.removeValue(forKey: id)
    }
}

public actor InMemoryRuntimeProfileRepository: RuntimeProfileRepository {
    private var storage: [RuntimeProfile.ID: RuntimeProfile] = [:]

    public init() {}

    public func list(projectID: Project.ID) async throws -> [RuntimeProfile] {
        storage.values.filter { $0.projectID == projectID }.sorted { $0.name < $1.name }
    }

    public func get(id: RuntimeProfile.ID) async throws -> RuntimeProfile? {
        storage[id]
    }

    public func save(_ profile: RuntimeProfile) async throws {
        storage[profile.id] = profile
    }

    public func delete(id: RuntimeProfile.ID) async throws {
        storage.removeValue(forKey: id)
    }
}

public actor InMemoryEnvSetRepository: EnvSetRepository {
    private var storage: [EnvSet.ID: EnvSet] = [:]

    public init() {}

    public func list(projectID: Project.ID) async throws -> [EnvSet] {
        storage.values.filter { $0.projectID == projectID }.sorted { $0.name < $1.name }
    }

    public func get(id: EnvSet.ID) async throws -> EnvSet? {
        storage[id]
    }

    public func save(_ envSet: EnvSet) async throws {
        storage[envSet.id] = envSet
    }

    public func delete(id: EnvSet.ID) async throws {
        storage.removeValue(forKey: id)
    }
}

public actor InMemoryRunSessionRepository: RunSessionRepository {
    private var storage: [RunSession.ID: RunSession] = [:]

    public init() {}

    public func list(projectID: Project.ID, limit: Int) async throws -> [RunSession] {
        Array(
            storage.values
                .filter { $0.projectID == projectID }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    public func listAll(limit: Int, status: RunSessionStatus?) async throws -> [RunSession] {
        Array(
            storage.values
                .filter { status == nil || $0.status == status }
                .sorted { $0.startedAt > $1.startedAt }
                .prefix(limit)
        )
    }

    public func listRunning() async throws -> [RunSession] {
        storage.values
            .filter { $0.status == .running }
            .sorted { $0.startedAt > $1.startedAt }
    }

    public func get(id: RunSession.ID) async throws -> RunSession? {
        storage[id]
    }

    public func save(_ session: RunSession) async throws {
        storage[session.id] = session
    }

    public func update(_ session: RunSession) async throws {
        storage[session.id] = session
    }
}

public actor InMemoryMilestoneRepository: MilestoneRepository {
    private var storage: [Milestone.ID: Milestone] = [:]

    public init() {}

    public func list(projectID: Project.ID) async throws -> [Milestone] {
        storage.values.filter { $0.projectID == projectID }.sorted { $0.title < $1.title }
    }

    public func get(id: Milestone.ID) async throws -> Milestone? {
        storage[id]
    }

    public func save(_ milestone: Milestone) async throws {
        storage[milestone.id] = milestone
    }

    public func delete(id: Milestone.ID) async throws {
        storage.removeValue(forKey: id)
    }
}

public actor InMemoryProjectNoteRepository: ProjectNoteRepository {
    private var storage: [Project.ID: ProjectNote] = [:]

    public init() {}

    public func get(projectID: Project.ID) async throws -> ProjectNote? {
        storage[projectID]
    }

    public func save(_ note: ProjectNote) async throws {
        storage[note.projectID] = note
    }
}
