import Foundation

actor WorkspaceLocalCommandRunner {
    func execute(_ command: CommandDescriptor) async throws -> CommandExecutionResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [command.executable] + command.arguments
            process.currentDirectoryURL = URL(fileURLWithPath: command.workingDirectory, isDirectory: true)
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
                let merged = stdoutData + stderrData
                let output = String(data: merged, encoding: .utf8) ?? ""

                continuation.resume(
                    returning: CommandExecutionResult(
                        command: command,
                        exitCode: process.terminationStatus,
                        output: output,
                        executedAt: Date()
                    )
                )
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
