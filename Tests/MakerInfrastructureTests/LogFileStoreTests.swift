import Foundation
import Testing
import MakerInfrastructure
import MakerSupport

@Test
func logFileStorePersistsEventText() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LogFileStore(logsDirectory: tempDirectory)
    let sessionID = UUID()

    try await store.append(LogEvent(stream: .stdout, message: "hello"), sessionID: sessionID)

    let text = await store.recentLogText(sessionID: sessionID)
    #expect(text?.contains("hello") == true)
}

@Test
func logFileStoreReturnsTailLinesInOrder() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LogFileStore(logsDirectory: tempDirectory)
    let sessionID = UUID()

    try await store.append(LogEvent(stream: .stdout, message: "line-1"), sessionID: sessionID)
    try await store.append(LogEvent(stream: .stdout, message: "line-2"), sessionID: sessionID)
    try await store.append(LogEvent(stream: .stdout, message: "line-3"), sessionID: sessionID)

    let chunk = await store.readRecent(sessionID: sessionID, tail: 2)
    #expect(chunk.lines.count == 2)
    #expect(chunk.lines[0].contains("line-2"))
    #expect(chunk.lines[1].contains("line-3"))
    #expect(chunk.nextLine == 3)
}

@Test
func logFileStoreReturnsLinesAfterCursor() async throws {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let store = LogFileStore(logsDirectory: tempDirectory)
    let sessionID = UUID()

    try await store.append(LogEvent(stream: .stdout, message: "line-1"), sessionID: sessionID)
    try await store.append(LogEvent(stream: .stdout, message: "line-2"), sessionID: sessionID)
    try await store.append(LogEvent(stream: .stdout, message: "line-3"), sessionID: sessionID)

    let chunk = await store.readAfter(sessionID: sessionID, line: 1)
    #expect(chunk.lines.count == 2)
    #expect(chunk.lines[0].contains("line-2"))
    #expect(chunk.lines[1].contains("line-3"))
    #expect(chunk.nextLine == 3)
}
