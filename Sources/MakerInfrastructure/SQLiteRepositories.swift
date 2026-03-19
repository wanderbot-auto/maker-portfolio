import Foundation
import MakerApplication
import MakerDomain
import SQLite3

public actor SQLiteProjectRepository: ProjectRepository {
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func list() async throws -> [Project] {
        let rows = try database.query("SELECT * FROM projects ORDER BY updated_at DESC;")
        return try rows.map(decodeProject)
    }

    public func get(id: Project.ID) async throws -> Project? {
        let rows = try database.query("SELECT * FROM projects WHERE id = ? LIMIT 1;", bindings: [.text(id.uuidString)])
        return try rows.first.map(decodeProject)
    }

    public func save(_ project: Project) async throws {
        try database.execute(
            """
            INSERT INTO projects (
                id, name, slug, local_path, repo_type, description, status, priority, tags_json,
                stack_summary, last_opened_at, archived_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                slug = excluded.slug,
                local_path = excluded.local_path,
                repo_type = excluded.repo_type,
                description = excluded.description,
                status = excluded.status,
                priority = excluded.priority,
                tags_json = excluded.tags_json,
                stack_summary = excluded.stack_summary,
                last_opened_at = excluded.last_opened_at,
                archived_at = excluded.archived_at,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(project.id.uuidString),
                .text(project.name),
                .text(project.slug),
                .text(project.localPath),
                .text(project.repoType.rawValue),
                .text(project.description),
                .text(project.status.rawValue),
                .text(project.priority.rawValue),
                .text(try encode(project.tags)),
                .text(project.stackSummary),
                project.lastOpenedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                project.archivedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                .real(project.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    public func archive(id: Project.ID, at: Date) async throws {
        try database.execute(
            """
            UPDATE projects
            SET status = ?, archived_at = ?, updated_at = ?
            WHERE id = ?;
            """,
            bindings: [
                .text(ProjectStatus.archived.rawValue),
                .real(at.timeIntervalSince1970),
                .real(at.timeIntervalSince1970),
                .text(id.uuidString)
            ]
        )
    }

    public func delete(id: Project.ID) async throws {
        try database.execute("DELETE FROM projects WHERE id = ?;", bindings: [.text(id.uuidString)])
    }

    private func decodeProject(from row: SQLiteRow) throws -> Project {
        Project(
            id: try uuid(row, "id"),
            name: try text(row, "name"),
            slug: try text(row, "slug"),
            localPath: try text(row, "local_path"),
            repoType: try enumValue(row, "repo_type"),
            description: try text(row, "description"),
            status: try enumValue(row, "status"),
            priority: try enumValue(row, "priority"),
            tags: try decode([String].self, from: try text(row, "tags_json")),
            stackSummary: try text(row, "stack_summary"),
            lastOpenedAt: optionalDate(row, "last_opened_at"),
            archivedAt: optionalDate(row, "archived_at"),
            updatedAt: try date(row, "updated_at")
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }
}

public actor SQLiteRuntimeProfileRepository: RuntimeProfileRepository {
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func list(projectID: Project.ID) async throws -> [RuntimeProfile] {
        let rows = try database.query(
            "SELECT * FROM runtime_profiles WHERE project_id = ? ORDER BY name ASC;",
            bindings: [.text(projectID.uuidString)]
        )
        return try rows.map(decodeProfile)
    }

    public func get(id: RuntimeProfile.ID) async throws -> RuntimeProfile? {
        let rows = try database.query(
            "SELECT * FROM runtime_profiles WHERE id = ? LIMIT 1;",
            bindings: [.text(id.uuidString)]
        )
        return try rows.first.map(decodeProfile)
    }

    public func save(_ profile: RuntimeProfile) async throws {
        try database.execute(
            """
            INSERT INTO runtime_profiles (
                id, project_id, name, entry_command, working_dir, args_json, env_set_id,
                health_check_type, health_check_target, depends_on_json, adapter_type, auto_restart
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_id = excluded.project_id,
                name = excluded.name,
                entry_command = excluded.entry_command,
                working_dir = excluded.working_dir,
                args_json = excluded.args_json,
                env_set_id = excluded.env_set_id,
                health_check_type = excluded.health_check_type,
                health_check_target = excluded.health_check_target,
                depends_on_json = excluded.depends_on_json,
                adapter_type = excluded.adapter_type,
                auto_restart = excluded.auto_restart;
            """,
            bindings: [
                .text(profile.id.uuidString),
                .text(profile.projectID.uuidString),
                .text(profile.name),
                .text(profile.entryCommand),
                .text(profile.workingDir),
                .text(try encode(profile.args)),
                profile.envSetID.map { .text($0.uuidString) } ?? .null,
                .text(profile.healthCheckType.rawValue),
                profile.healthCheckTarget.map(SQLiteValue.text) ?? .null,
                .text(try encode(profile.dependsOn.map(\.uuidString))),
                .text(profile.adapterType.rawValue),
                .integer(profile.autoRestart ? 1 : 0)
            ]
        )
    }

    public func delete(id: RuntimeProfile.ID) async throws {
        try database.execute("DELETE FROM runtime_profiles WHERE id = ?;", bindings: [.text(id.uuidString)])
    }

    private func decodeProfile(from row: SQLiteRow) throws -> RuntimeProfile {
        let dependencyIDs = try decode([String].self, from: try text(row, "depends_on_json")).compactMap(UUID.init(uuidString:))
        return try RuntimeProfile(
            id: uuid(row, "id"),
            projectID: uuid(row, "project_id"),
            name: text(row, "name"),
            entryCommand: text(row, "entry_command"),
            workingDir: text(row, "working_dir"),
            args: decode([String].self, from: text(row, "args_json")),
            envSetID: optionalUUID(row, "env_set_id"),
            healthCheckType: enumValue(row, "health_check_type"),
            healthCheckTarget: optionalText(row, "health_check_target"),
            dependsOn: dependencyIDs,
            adapterType: enumValue(row, "adapter_type"),
            autoRestart: integer(row, "auto_restart") == 1
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }
}

public actor SQLiteEnvSetRepository: EnvSetRepository {
    private let database: SQLiteDatabase
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func list(projectID: Project.ID) async throws -> [EnvSet] {
        let rows = try database.query(
            "SELECT * FROM env_sets WHERE project_id = ? ORDER BY name ASC;",
            bindings: [.text(projectID.uuidString)]
        )
        return try rows.map(decodeEnvSet)
    }

    public func get(id: EnvSet.ID) async throws -> EnvSet? {
        let rows = try database.query("SELECT * FROM env_sets WHERE id = ? LIMIT 1;", bindings: [.text(id.uuidString)])
        return try rows.first.map(decodeEnvSet)
    }

    public func save(_ envSet: EnvSet) async throws {
        try database.execute(
            """
            INSERT INTO env_sets (id, project_id, name, variables_json, is_encrypted, scope)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_id = excluded.project_id,
                name = excluded.name,
                variables_json = excluded.variables_json,
                is_encrypted = excluded.is_encrypted,
                scope = excluded.scope;
            """,
            bindings: [
                .text(envSet.id.uuidString),
                .text(envSet.projectID.uuidString),
                .text(envSet.name),
                .text(try encode(envSet.variables)),
                .integer(envSet.isEncrypted ? 1 : 0),
                .text(envSet.scope.rawValue)
            ]
        )
    }

    public func delete(id: EnvSet.ID) async throws {
        try database.execute("DELETE FROM env_sets WHERE id = ?;", bindings: [.text(id.uuidString)])
    }

    private func decodeEnvSet(from row: SQLiteRow) throws -> EnvSet {
        try EnvSet(
            id: uuid(row, "id"),
            projectID: uuid(row, "project_id"),
            name: text(row, "name"),
            variables: decode([String: String].self, from: text(row, "variables_json")),
            isEncrypted: integer(row, "is_encrypted") == 1,
            scope: enumValue(row, "scope")
        )
    }

    private func encode<T: Encodable>(_ value: T) throws -> String {
        String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }
}

public actor SQLiteRunSessionRepository: RunSessionRepository {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func list(projectID: Project.ID, limit: Int) async throws -> [RunSession] {
        let rows = try database.query(
            "SELECT * FROM run_sessions WHERE project_id = ? ORDER BY started_at DESC LIMIT ?;",
            bindings: [.text(projectID.uuidString), .integer(Int64(limit))]
        )
        return try rows.map(decodeSession)
    }

    public func listAll(limit: Int, status: RunSessionStatus?) async throws -> [RunSession] {
        let safeLimit = max(1, limit)
        let rows: [SQLiteRow]
        if let status {
            rows = try database.query(
                "SELECT * FROM run_sessions WHERE status = ? ORDER BY started_at DESC LIMIT ?;",
                bindings: [.text(status.rawValue), .integer(Int64(safeLimit))]
            )
        } else {
            rows = try database.query(
                "SELECT * FROM run_sessions ORDER BY started_at DESC LIMIT ?;",
                bindings: [.integer(Int64(safeLimit))]
            )
        }
        return try rows.map(decodeSession)
    }

    public func listRunning() async throws -> [RunSession] {
        let rows = try database.query(
            "SELECT * FROM run_sessions WHERE status = ? ORDER BY started_at DESC;",
            bindings: [.text(RunSessionStatus.running.rawValue)]
        )
        return try rows.map(decodeSession)
    }

    public func get(id: RunSession.ID) async throws -> RunSession? {
        let rows = try database.query("SELECT * FROM run_sessions WHERE id = ? LIMIT 1;", bindings: [.text(id.uuidString)])
        return try rows.first.map(decodeSession)
    }

    public func save(_ session: RunSession) async throws {
        try await persist(session)
    }

    public func update(_ session: RunSession) async throws {
        try await persist(session)
    }

    private func persist(_ session: RunSession) async throws {
        try database.execute(
            """
            INSERT INTO run_sessions (
                id, project_id, runtime_profile_id, status, pid, started_at, ended_at, exit_code, trigger_source,
                restart_count, failure_reason, last_health_check_status, last_health_check_detail, last_health_check_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_id = excluded.project_id,
                runtime_profile_id = excluded.runtime_profile_id,
                status = excluded.status,
                pid = excluded.pid,
                started_at = excluded.started_at,
                ended_at = excluded.ended_at,
                exit_code = excluded.exit_code,
                trigger_source = excluded.trigger_source,
                restart_count = excluded.restart_count,
                failure_reason = excluded.failure_reason,
                last_health_check_status = excluded.last_health_check_status,
                last_health_check_detail = excluded.last_health_check_detail,
                last_health_check_at = excluded.last_health_check_at;
            """,
            bindings: [
                .text(session.id.uuidString),
                .text(session.projectID.uuidString),
                .text(session.runtimeProfileID.uuidString),
                .text(session.status.rawValue),
                session.pid.map { .integer(Int64($0)) } ?? .null,
                .real(session.startedAt.timeIntervalSince1970),
                session.endedAt.map { .real($0.timeIntervalSince1970) } ?? .null,
                session.exitCode.map { .integer(Int64($0)) } ?? .null,
                .text(session.triggerSource.rawValue),
                .integer(Int64(session.restartCount)),
                session.failureReason.map(SQLiteValue.text) ?? .null,
                session.lastHealthCheckStatus.map { .text($0.rawValue) } ?? .null,
                session.lastHealthCheckDetail.map(SQLiteValue.text) ?? .null,
                session.lastHealthCheckAt.map { .real($0.timeIntervalSince1970) } ?? .null
            ]
        )
    }

    private func decodeSession(from row: SQLiteRow) throws -> RunSession {
        try RunSession(
            id: uuid(row, "id"),
            projectID: uuid(row, "project_id"),
            runtimeProfileID: uuid(row, "runtime_profile_id"),
            status: enumValue(row, "status"),
            pid: optionalInteger(row, "pid").map(Int32.init),
            startedAt: date(row, "started_at"),
            endedAt: optionalDate(row, "ended_at"),
            exitCode: optionalInteger(row, "exit_code").map(Int32.init),
            triggerSource: enumValue(row, "trigger_source"),
            restartCount: Int(optionalInteger(row, "restart_count") ?? 0),
            failureReason: optionalText(row, "failure_reason"),
            lastHealthCheckStatus: optionalEnumValue(row, "last_health_check_status"),
            lastHealthCheckDetail: optionalText(row, "last_health_check_detail"),
            lastHealthCheckAt: optionalDate(row, "last_health_check_at")
        )
    }
}

public actor SQLiteMilestoneRepository: MilestoneRepository {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func list(projectID: Project.ID) async throws -> [Milestone] {
        let rows = try database.query(
            "SELECT * FROM milestones WHERE project_id = ? ORDER BY title ASC;",
            bindings: [.text(projectID.uuidString)]
        )
        return try rows.map(decodeMilestone)
    }

    public func get(id: Milestone.ID) async throws -> Milestone? {
        let rows = try database.query(
            "SELECT * FROM milestones WHERE id = ? LIMIT 1;",
            bindings: [.text(id.uuidString)]
        )
        return try rows.first.map(decodeMilestone)
    }

    public func save(_ milestone: Milestone) async throws {
        try database.execute(
            """
            INSERT INTO milestones (id, project_id, title, due_date, state)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                project_id = excluded.project_id,
                title = excluded.title,
                due_date = excluded.due_date,
                state = excluded.state;
            """,
            bindings: [
                .text(milestone.id.uuidString),
                .text(milestone.projectID.uuidString),
                .text(milestone.title),
                milestone.dueDate.map { .real($0.timeIntervalSince1970) } ?? .null,
                .text(milestone.state.rawValue)
            ]
        )
    }

    public func delete(id: Milestone.ID) async throws {
        try database.execute(
            "DELETE FROM milestones WHERE id = ?;",
            bindings: [.text(id.uuidString)]
        )
    }

    private func decodeMilestone(from row: SQLiteRow) throws -> Milestone {
        try Milestone(
            id: uuid(row, "id"),
            projectID: uuid(row, "project_id"),
            title: text(row, "title"),
            dueDate: optionalDate(row, "due_date"),
            state: enumValue(row, "state")
        )
    }
}

public actor SQLiteProjectNoteRepository: ProjectNoteRepository {
    private let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func get(projectID: Project.ID) async throws -> ProjectNote? {
        let rows = try database.query(
            "SELECT * FROM project_notes WHERE project_id = ? LIMIT 1;",
            bindings: [.text(projectID.uuidString)]
        )
        return try rows.first.map(decodeNote)
    }

    public func save(_ note: ProjectNote) async throws {
        try database.execute(
            """
            INSERT INTO project_notes (id, project_id, content, updated_at)
            VALUES (?, ?, ?, ?)
            ON CONFLICT(project_id) DO UPDATE SET
                id = excluded.id,
                content = excluded.content,
                updated_at = excluded.updated_at;
            """,
            bindings: [
                .text(note.id.uuidString),
                .text(note.projectID.uuidString),
                .text(note.content),
                .real(note.updatedAt.timeIntervalSince1970)
            ]
        )
    }

    private func decodeNote(from row: SQLiteRow) throws -> ProjectNote {
        try ProjectNote(
            id: uuid(row, "id"),
            projectID: uuid(row, "project_id"),
            content: text(row, "content"),
            updatedAt: date(row, "updated_at")
        )
    }
}

private func text(_ row: SQLiteRow, _ column: String) throws -> String {
    guard let value = row[column]?.stringValue else {
        throw SQLiteError(code: SQLITE_MISMATCH, message: "Expected text in column \(column)")
    }
    return value
}

private func optionalText(_ row: SQLiteRow, _ column: String) -> String? {
    row[column]?.stringValue
}

private func integer(_ row: SQLiteRow, _ column: String) throws -> Int64 {
    guard let value = row[column]?.int64Value else {
        throw SQLiteError(code: SQLITE_MISMATCH, message: "Expected integer in column \(column)")
    }
    return value
}

private func optionalInteger(_ row: SQLiteRow, _ column: String) -> Int64? {
    row[column]?.int64Value
}

private func date(_ row: SQLiteRow, _ column: String) throws -> Date {
    guard let value = row[column]?.doubleValue else {
        throw SQLiteError(code: SQLITE_MISMATCH, message: "Expected date in column \(column)")
    }
    return Date(timeIntervalSince1970: value)
}

private func optionalDate(_ row: SQLiteRow, _ column: String) -> Date? {
    row[column]?.doubleValue.map(Date.init(timeIntervalSince1970:))
}

private func uuid(_ row: SQLiteRow, _ column: String) throws -> UUID {
    guard let string = row[column]?.stringValue, let value = UUID(uuidString: string) else {
        throw SQLiteError(code: SQLITE_MISMATCH, message: "Expected UUID in column \(column)")
    }
    return value
}

private func optionalUUID(_ row: SQLiteRow, _ column: String) -> UUID? {
    guard let string = row[column]?.stringValue else {
        return nil
    }
    return UUID(uuidString: string)
}

private func enumValue<T: RawRepresentable>(_ row: SQLiteRow, _ column: String) throws -> T where T.RawValue == String {
    guard let value = row[column]?.stringValue, let typed = T(rawValue: value) else {
        throw SQLiteError(code: SQLITE_MISMATCH, message: "Expected enum raw value in column \(column)")
    }
    return typed
}

private func optionalEnumValue<T: RawRepresentable>(_ row: SQLiteRow, _ column: String) -> T? where T.RawValue == String {
    guard let value = row[column]?.stringValue else {
        return nil
    }
    return T(rawValue: value)
}
