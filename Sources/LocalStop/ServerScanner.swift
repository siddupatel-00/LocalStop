import Darwin
import Foundation

struct LocalServer: Identifiable, Equatable {
    let pid: Int32
    let command: String
    let port: Int
    let address: String

    var id: String { "\(pid)-\(port)-\(address)" }
}

enum ServerScanner {
    private static let ignoredCommands: Set<String> = [
        "ControlCenter", "rapportd", "sharingd", "nearbyd",
        "identityservicesd", "AirPlayUIAgent", "WiFiAgent", "cloudd",
        "Code Helper", "Cursor Helper", "OpenCode", "OpenCode Helper"
    ]

    static func scan() -> [LocalServer] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = [
            "-nP", "-a", "+c", "0", "-iTCP", "-sTCP:LISTEN",
            "-u", String(getuid()), "-Fpcn"
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(decoding: data, as: UTF8.self)
        return parse(output)
    }

    private static func parse(_ output: String) -> [LocalServer] {
        var servers: [LocalServer] = []
        var seenKeys = Set<String>()
        var pid: Int32?
        var command = ""

        for rawLine in output.split(separator: "\n") {
            let line = String(rawLine)
            guard let field = line.first else { continue }
            let value = String(line.dropFirst())

            switch field {
            case "p":
                pid = Int32(value)
                command = ""
            case "c":
                command = value
            case "n":
                guard let pid, pid > 1, pid != getpid() else { continue }
                guard !ignoredCommands.contains(command) else { continue }
                guard let port = port(from: value), port > 0, port <= 65535 else { continue }
                let addr = address(from: value)
                guard seenKeys.insert("\(pid)-\(port)-\(addr)").inserted else { continue }
                servers.append(
                    LocalServer(
                        pid: pid,
                        command: command,
                        port: port,
                        address: addr
                    )
                )
            default:
                break
            }
        }

        return servers.sorted { $0.port < $1.port }
    }

    private static func port(from name: String) -> Int? {
        guard let colon = name.lastIndex(of: ":") else { return nil }
        return Int(name[name.index(after: colon)...])
    }

    private static func address(from name: String) -> String {
        guard let colon = name.lastIndex(of: ":") else { return name }
        let host = String(name[..<colon])
        if host.isEmpty || host == "*" { return "localhost" }
        return host
    }

    static func stop(_ server: LocalServer) -> Bool {
        guard server.pid > 1, server.pid != getpid() else { return false }

        if kill(server.pid, SIGTERM) != 0 {
            if errno != ESRCH { return false }
        }

        for _ in 0..<10 {
            usleep(200_000)
            let rc = kill(server.pid, 0)
            let err = errno
            if rc != 0 {
                if err == ESRCH { return true }
                return false
            }
        }

        if kill(server.pid, SIGKILL) == 0 {
            return true
        }
        return errno == ESRCH
    }
}
