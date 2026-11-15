import Foundation

enum ProcessRunner {
    struct Result: Sendable {
        var status: Int32
        var stdout: String
        var stderr: String
        var timedOut: Bool

        var combined: String {
            [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        }
    }

    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        stdin: Data? = nil,
        timeout: TimeInterval? = nil
    ) async -> Result {
        await Task.detached(priority: .userInitiated) {
            runSync(executable: executable, arguments: arguments, environment: environment, stdin: stdin, timeout: timeout)
        }.value
    }

    private static func runSync(
        executable: String,
        arguments: [String],
        environment: [String: String]?,
        stdin: Data?,
        timeout: TimeInterval?
    ) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment {
            process.environment = environment
        }
        let inputPipe = Pipe()
        if stdin != nil {
            process.standardInput = inputPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(status: -1, stdout: "", stderr: error.localizedDescription, timedOut: false)
        }
        if let stdin {
            try? inputPipe.fileHandleForWriting.write(contentsOf: stdin)
            try? inputPipe.fileHandleForWriting.close()
        }

        let timedOut = Flag()
        if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning {
                    timedOut.value = true
                    process.terminate()
                }
            }
        }

        let output = PipeBuffer()
        let errors = PipeBuffer()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            output.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errors.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: output.data, as: UTF8.self),
            stderr: String(decoding: errors.data, as: UTF8.self),
            timedOut: timedOut.value
        )
    }
}

private final class Flag: @unchecked Sendable {
    var value = false
}

private final class PipeBuffer: @unchecked Sendable {
    var data = Data()
}
