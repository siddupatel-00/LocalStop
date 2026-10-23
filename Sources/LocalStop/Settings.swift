import Foundation

enum SortMode: String, CaseIterable {
    case port
    case name
    case pid

    var label: String {
        switch self {
        case .port: return "Port"
        case .name: return "Name"
        case .pid: return "PID"
        }
    }

    var next: SortMode {
        switch self {
        case .port: return .name
        case .name: return .pid
        case .pid: return .port
        }
    }
}

final class Settings {
    static let shared = Settings()

    private enum Key {
        static let serverNames = "localstop.serverNames"
        static let sortMode = "localstop.sortMode"
    }

    private let defaults = UserDefaults.standard
    private let lock = NSLock()
    private var _serverNames: [String: String]
    private var _sortMode: SortMode

    private(set) var serverNames: [String: String] {
        get { lock.lock(); defer { lock.unlock() }; return _serverNames }
        set { lock.lock(); defer { lock.unlock() }; _serverNames = newValue }
    }

    var sortMode: SortMode {
        get { lock.lock(); defer { lock.unlock() }; return _sortMode }
        set {
            lock.lock(); _sortMode = newValue; lock.unlock()
            defaults.set(newValue.rawValue, forKey: Key.sortMode)
        }
    }

    private init() {
        if let dict = defaults.dictionary(forKey: Key.serverNames) {
            var result: [String: String] = [:]
            for (k, v) in dict {
                if let s = v as? String { result[k] = s }
            }
            _serverNames = result
        } else {
            _serverNames = [:]
        }

        if let raw = defaults.string(forKey: Key.sortMode),
           let mode = SortMode(rawValue: raw) {
            _sortMode = mode
        } else {
            _sortMode = .port
            defaults.set(SortMode.port.rawValue, forKey: Key.sortMode)
        }
    }

    func customName(for port: Int) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let name = _serverNames[String(port)]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else {
            return nil
        }
        return name
    }

    func setCustomName(_ name: String, for port: Int) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        lock.lock()
        if trimmed.isEmpty {
            _serverNames.removeValue(forKey: String(port))
        } else {
            _serverNames[String(port)] = trimmed
        }
        let snapshot = _serverNames
        lock.unlock()

        defaults.set(snapshot, forKey: Key.serverNames)
    }
}
