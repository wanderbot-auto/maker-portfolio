import Foundation
import Testing
import MakerApplication
import MakerDomain

@Test
func createProjectUseCasePersistsScannedProject() async throws {
    let repository = ProjectRepositorySpy()
    let scanner = ProjectScannerStub()
    let useCase = CreateProjectUseCase(projects: repository, scanner: scanner)

    let project = try await useCase.execute(path: "/tmp/example")

    #expect(project.name == "Example")
    let stored = try await repository.list()
    #expect(stored.count == 1)
}

actor ProjectRepositorySpy: ProjectRepository {
    private var projects: [Project.ID: Project] = [:]

    func list() async throws -> [Project] {
        Array(projects.values)
    }

    func get(id: Project.ID) async throws -> Project? {
        projects[id]
    }

    func save(_ project: Project) async throws {
        projects[project.id] = project
    }

    func archive(id: Project.ID, at: Date) async throws {
        guard var project = projects[id] else { return }
        project.status = .archived
        project.archivedAt = at
        project.updatedAt = at
        projects[id] = project
    }

    func delete(id: Project.ID) async throws {
        projects.removeValue(forKey: id)
    }
}

struct ProjectScannerStub: ProjectScanner {
    func scan(at path: String) async throws -> ProjectScanResult {
        ProjectScanResult(suggestedName: "Example", repoType: .git, stackSummary: "Swift")
    }
}
