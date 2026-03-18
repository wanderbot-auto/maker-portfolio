import Foundation
import MakerSupport
import SQLite3

public enum SQLiteValue: Sendable, Equatable {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
    case null

    public var int64Value: Int64? {
        if case let .integer(value) = self { return value }
        return nil
    }

    public var doubleValue: Double? {
        switch self {
        case let .real(value):
            return value
        case let .integer(value):
            return Double(value)
        default:
            return nil
        }
    }

    public var stringValue: String? {
        if case let .text(value) = self { return value }
        return nil
    }
}

public struct SQLiteRow: Sendable, Equatable {
    private let storage: [String: SQLiteValue]

    public init(storage: [String: SQLiteValue]) {
        self.storage = storage
    }

    public subscript(_ column: String) -> SQLiteValue? {
        storage[column]
    }
}

public struct SQLiteError: LocalizedError, Sendable {
    public let code: Int32
    public let message: String
    public let sql: String?

    public init(code: Int32, message: String, sql: String? = nil) {
        self.code = code
        self.message = message
        self.sql = sql
    }

    public var errorDescription: String? {
        if let sql {
            return "SQLite error \(code): \(message). SQL: \(sql)"
        }
        return "SQLite error \(code): \(message)"
    }
}

public final class SQLiteDatabase: @unchecked Sendable {
    private let path: String
    private var handle: OpaquePointer?

    public init(path: String) throws {
        self.path = path
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK, let handle else {
            let message = handle.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? "Unable to open database"
            throw SQLiteError(code: result, message: message)
        }
        self.handle = handle
        try executeScript("PRAGMA foreign_keys = ON;")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    public func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement, sql: sql)

        let result = sqlite3_step(statement)
        guard result == SQLITE_DONE else {
            throw currentError(sql: sql)
        }
    }

    public func executeScript(_ sql: String) throws {
        try withHandle { handle in
            var errorMessage: UnsafeMutablePointer<Int8>?
            let result = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
            guard result == SQLITE_OK else {
                let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errorMessage)
                throw SQLiteError(code: result, message: message, sql: sql)
            }
        }
    }

    public func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        let statement = try prepareStatement(sql)
        defer { sqlite3_finalize(statement) }
        try bind(bindings, to: statement, sql: sql)

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            switch result {
            case SQLITE_ROW:
                rows.append(makeRow(from: statement))
            case SQLITE_DONE:
                return rows
            default:
                throw currentError(sql: sql)
            }
        }
    }

    public func scalar(_ sql: String, bindings: [SQLiteValue] = []) throws -> SQLiteValue? {
        try query(sql, bindings: bindings).first?["value"]
    }

    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        try withHandle { handle in
            var statement: OpaquePointer?
            let result = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
            guard result == SQLITE_OK, let statement else {
                throw currentError(sql: sql)
            }
            return statement
        }
    }

    private func bind(_ bindings: [SQLiteValue], to statement: OpaquePointer, sql: String) throws {
        for (index, value) in bindings.enumerated() {
            let position = Int32(index + 1)
            let result: Int32
            switch value {
            case let .integer(integer):
                result = sqlite3_bind_int64(statement, position, integer)
            case let .real(double):
                result = sqlite3_bind_double(statement, position, double)
            case let .text(text):
                result = sqlite3_bind_text(statement, position, text, -1, SQLITE_TRANSIENT)
            case let .blob(data):
                result = data.withUnsafeBytes { buffer in
                    sqlite3_bind_blob(statement, position, buffer.baseAddress, Int32(buffer.count), SQLITE_TRANSIENT)
                }
            case .null:
                result = sqlite3_bind_null(statement, position)
            }

            guard result == SQLITE_OK else {
                throw currentError(sql: sql)
            }
        }
    }

    private func makeRow(from statement: OpaquePointer) -> SQLiteRow {
        var values: [String: SQLiteValue] = [:]
        let count = sqlite3_column_count(statement)
        for index in 0..<count {
            let name = String(cString: sqlite3_column_name(statement, index))
            values[name] = columnValue(statement: statement, index: index)
        }
        return SQLiteRow(storage: values)
    }

    private func columnValue(statement: OpaquePointer, index: Int32) -> SQLiteValue {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
            guard let pointer = sqlite3_column_text(statement, index) else {
                return .null
            }
            return .text(String(cString: pointer))
        case SQLITE_BLOB:
            guard let pointer = sqlite3_column_blob(statement, index) else {
                return .null
            }
            let count = Int(sqlite3_column_bytes(statement, index))
            return .blob(Data(bytes: pointer, count: count))
        default:
            return .null
        }
    }

    private func currentError(sql: String? = nil) -> SQLiteError {
        guard let handle else {
            return SQLiteError(code: -1, message: "Database handle is unavailable", sql: sql)
        }
        return SQLiteError(
            code: sqlite3_errcode(handle),
            message: String(cString: sqlite3_errmsg(handle)),
            sql: sql
        )
    }

    private func withHandle<T>(_ operation: (OpaquePointer) throws -> T) throws -> T {
        guard let handle else {
            throw MakerError.missingResource("SQLite database handle is unavailable")
        }
        return try operation(handle)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
