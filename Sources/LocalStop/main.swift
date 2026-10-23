import AppKit

if CommandLine.arguments.contains("--scan") {
    for server in ServerScanner.scan() {
        print("\(server.port)\t\(server.command)\tpid \(server.pid)\t\(server.address)")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
