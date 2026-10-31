import Foundation

struct CommandResult {
    let status: Int32
    let output: String
    let error: String

    var ok: Bool { status == 0 }
    var cancelled: Bool { error.contains("-128") || error.localizedCaseInsensitiveContains("User canceled") }
}

enum Shell {
    static func run(_ executable: String, _ arguments: [String] = []) async -> CommandResult {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            let out = Pipe()
            let err = Pipe()
            process.standardOutput = out
            process.standardError = err
            do {
                try process.run()
            } catch {
                return CommandResult(status: -1, output: "", error: error.localizedDescription)
            }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(
                status: process.terminationStatus,
                output: String(decoding: outData, as: UTF8.self),
                error: String(decoding: errData, as: UTF8.self)
            )
        }.value
    }

    /// Runs a shell script as root behind the standard macOS administrator prompt.
    static func runAsAdmin(_ script: String) async -> CommandResult {
        let escaped = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return await run("/usr/bin/osascript", ["-e", "do shell script \"\(escaped)\" with administrator privileges"])
    }

    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
