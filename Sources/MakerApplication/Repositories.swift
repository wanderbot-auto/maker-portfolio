import Foundation
import MakerDomain

public protocol ProjectRepository: Sendable {
    func list() async throws -> [Project]
    func get(id: Project.ID) async throws -> Project?
    func save(_ project: Project) async throws
    func archive(id: Project.ID, at: Date) async throws
    func delete(id: Project.ID) async throws
}

public protocol RuntimeProfileRepository: Sendable {
    func list(projectID: Project.ID) async throws -> [RuntimeProfile]
    func get(id: RuntimeProfile.ID) async throws -> RuntimeProfile?
    func save(_ profile: RuntimeProfile) async throws
    func delete(id: RuntimeProfile.ID) async throws
}

public protocol EnvSetRepository: Sendable {
    func list(projectID: Project.ID) async throws -> [EnvSet]
    func get(id: EnvSet.ID) async throws -> EnvSet?
    func save(_ envSet: EnvSet) async throws
    func delete(id: EnvSet.ID) async throws
}

public protocol RunSessionRepository: Sendable {
    func list(projectID: Project.ID, limit: Int) async throws -> [RunSession]
    func listAll(limit: Int, status: RunSessionStatus?) async throws -> [RunSession]
    func listRunning() async throws -> [RunSession]
    func get(id: RunSession.ID) async throws -> RunSession?
    func save(_ session: RunSession) async throws
    func update(_ session: RunSession) async throws
}

public protocol MilestoneRepository: Sendable {
    func list(projectID: Project.ID) async throws -> [Milestone]
    func get(id: Milestone.ID) async throws -> Milestone?
    func save(_ milestone: Milestone) async throws
    func delete(id: Milestone.ID) async throws
}

public protocol ProjectNoteRepository: Sendable {
    func get(projectID: Project.ID) async throws -> ProjectNote?
    func save(_ note: ProjectNote) async throws
}
