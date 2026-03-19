import Foundation
import MakerDomain
import MakerSupport

public actor LocalProcessAdapter: RuntimeAdapter {
    private var preparedProject: Project?
    private var preparedProfile: RuntimeProfile?
    private var preparedEnv: [String: String] = [:]
    private var process: Process?
    private var state: RuntimeProcessState = .idle
    private var continuation: AsyncThrowingStream<LogEvent, Error>.Continuation?
    private var lastExitCodeValue: Int32?
    private var isStopping = false

    public init() {}

    public func prepare(project: Project, profile: RuntimeProfile, env: [String: String]) async throws {
        preparedProject = project
        preparedProfile = profile
        preparedEnv = env
        state = .preparing
    }

    public func start() async throws -> RuntimeExecutionHandle {
        guard process == nil else {
            throw MakerError.processAlreadyRunning
        }
        guard let profile = preparedProfile else {
            throw MakerError.invalidConfiguration("Runtime profile has not been prepared.")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", shellCommand(for: profile)]
        process.currentDirectoryURL = URL(fileURLWithPath: profile.workingDir)
        process.environment = ProcessInfo.processInfo.environment.merging(preparedEnv) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        bind(pipe: stdout, stream: .stdout)
        bind(pipe: stderr, stream: .stderr)
        lastExitCodeValue = nil
        isStopping = false

        process.terminationHandler = { [weak self] terminatedProcess in
            Task {
                await self?.handleTermination(of: terminatedProcess)
            }
        }

        try process.run()
        self.process = process
        state = .running

        yield(.system, "Started \(profile.name) with PID \(process.processIdentifier)")
        return RuntimeExecutionHandle(pid: process.processIdentifier)
    }

    public func stop() async throws {
        guard let process else {
            throw MakerError.processNotRunning
        }

        isStopping = true
        process.terminate()
        yield(.system, "Stopped PID \(process.processIdentifier)")
    }

    public func restart() async throws -> RuntimeExecutionHandle {
        if process != nil {
            try await stop()
        }
        return try await start()
    }

    public func getStatus() async -> RuntimeProcessState {
        state
    }

    public func lastExitCode() async -> Int32? {
        lastExitCodeValue
    }

    public nonisolated func streamLogs() -> AsyncThrowingStream<LogEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                await install(continuation: continuation)
            }
        }
    }

    private func install(continuation: AsyncThrowingStream<LogEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    private func bind(pipe: Pipe, stream: LogEvent.Stream) {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else {
                return
            }
            Task {
                await self?.yield(stream, text.trimmingCharacters(in: .newlines))
            }
        }
    }

    private func handleTermination(of process: Process) {
        lastExitCodeValue = process.terminationStatus
        if isStopping || process.terminationStatus == 0 {
            state = .stopped
        } else {
            state = .failed
        }
        yield(.system, "Process exited with code \(process.terminationStatus)")
        self.process = nil
        isStopping = false
    }

    private func yield(_ stream: LogEvent.Stream, _ message: String) {
        guard !message.isEmpty else { return }
        continuation?.yield(LogEvent(stream: stream, message: message))
    }

    private func shellCommand(for profile: RuntimeProfile) -> String {
        ([profile.entryCommand] + profile.args).joined(separator: " ")
    }
}
