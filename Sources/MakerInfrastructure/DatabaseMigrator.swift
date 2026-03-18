import Foundation

public struct DatabaseMigrator {
    public let database: SQLiteDatabase

    public init(database: SQLiteDatabase) {
        self.database = database
    }

    public func migrate() throws {
        let versionRows = try database.query("PRAGMA user_version;")
        var version = versionRows.first?["user_version"]?.int64Value ?? 0

        if version < 1 {
            try database.executeScript("""
            PRAGMA journal_mode = WAL;

            CREATE TABLE IF NOT EXISTS projects (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                slug TEXT NOT NULL,
                local_path TEXT NOT NULL UNIQUE,
                repo_type TEXT NOT NULL,
                description TEXT NOT NULL,
                status TEXT NOT NULL,
                priority TEXT NOT NULL,
                tags_json TEXT NOT NULL,
                stack_summary TEXT NOT NULL,
                last_opened_at REAL,
                archived_at REAL,
                updated_at REAL NOT NULL
            );

            CREATE TABLE IF NOT EXISTS runtime_profiles (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                entry_command TEXT NOT NULL,
                working_dir TEXT NOT NULL,
                args_json TEXT NOT NULL,
                env_set_id TEXT,
                health_check_type TEXT NOT NULL,
                health_check_target TEXT,
                depends_on_json TEXT NOT NULL,
                adapter_type TEXT NOT NULL,
                auto_restart INTEGER NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE,
                FOREIGN KEY(env_set_id) REFERENCES env_sets(id) ON DELETE SET NULL
            );

            CREATE TABLE IF NOT EXISTS env_sets (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                name TEXT NOT NULL,
                variables_json TEXT NOT NULL,
                is_encrypted INTEGER NOT NULL,
                scope TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS run_sessions (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                runtime_profile_id TEXT NOT NULL,
                status TEXT NOT NULL,
                pid INTEGER,
                started_at REAL NOT NULL,
                ended_at REAL,
                exit_code INTEGER,
                trigger_source TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE,
                FOREIGN KEY(runtime_profile_id) REFERENCES runtime_profiles(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS milestones (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL,
                title TEXT NOT NULL,
                due_date REAL,
                state TEXT NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );

            CREATE TABLE IF NOT EXISTS project_notes (
                id TEXT PRIMARY KEY,
                project_id TEXT NOT NULL UNIQUE,
                content TEXT NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE
            );

            CREATE INDEX IF NOT EXISTS idx_runtime_profiles_project_id ON runtime_profiles(project_id);
            CREATE INDEX IF NOT EXISTS idx_env_sets_project_id ON env_sets(project_id);
            CREATE INDEX IF NOT EXISTS idx_run_sessions_project_id ON run_sessions(project_id, started_at DESC);
            CREATE INDEX IF NOT EXISTS idx_milestones_project_id ON milestones(project_id);

            PRAGMA user_version = 1;
            """)
            version = 1
        }

        if version < 2 {
            try database.executeScript("""
            CREATE TABLE IF NOT EXISTS env_set_secrets (
                env_set_id TEXT PRIMARY KEY,
                encrypted_blob BLOB NOT NULL,
                updated_at REAL NOT NULL,
                FOREIGN KEY(env_set_id) REFERENCES env_sets(id) ON DELETE CASCADE
            );

            PRAGMA user_version = 2;
            """)
        }
    }
}
