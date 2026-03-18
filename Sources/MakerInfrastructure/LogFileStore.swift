import Foundation
import MakerApplication
import MakerSupport

public actor LogFileStore: RuntimeLogReader {
    private let logsDirectory: URL
    private let fileManager: FileManager

    public init(logsDirectory: URL, fileManager: FileManager = .default) {
        self.logsDirectory = logsDirectory
        self.fileManager = fileManager
    }

    public func append(_ event: LogEvent, sessionID: UUID) throws {
        try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let fileURL = logsDirectory.appendingPathComponent("\(sessionID.uuidString).log")
        let line = "\(event.timestamp.ISO8601Format()) [\(event.stream.rawValue)] \(event.message)\n"
        let data = Data(line.utf8)

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: fileURL)
        }
    }

    public func recentLogText(sessionID: UUID) -> String? {
        let fileURL = logsDirectory.appendingPathComponent("\(sessionID.uuidString).log")
        guard let data = fileManager.contents(atPath: fileURL.path) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    public func readRecent(sessionID: UUID, tail: Int) -> RuntimeLogChunk {
        let lines = allLines(sessionID: sessionID)
        let sliced: [String]

        guard tail > 0, lines.count > tail else {
            sliced = lines
            return RuntimeLogChunk(lines: sliced, nextLine: lines.count)
        }

        sliced = Array(lines.suffix(tail))
        return RuntimeLogChunk(lines: sliced, nextLine: lines.count)
    }

    public func readAfter(sessionID: UUID, line: Int) -> RuntimeLogChunk {
        let lines = allLines(sessionID: sessionID)
        let safeIndex = max(0, min(line, lines.count))
        return RuntimeLogChunk(lines: Array(lines.dropFirst(safeIndex)), nextLine: lines.count)
    }

    private func allLines(sessionID: UUID) -> [String] {
        guard let text = recentLogText(sessionID: sessionID) else {
            return []
        }

        return text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }
}
