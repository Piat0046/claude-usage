import Foundation

enum ClaudeConfigError: LocalizedError {
    case fileNotFound
    case invalidJSON
    case writeFailed(Error)
    case readFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "Claude settings file not found"
        case .invalidJSON:
            return "Invalid JSON in settings file"
        case .writeFailed(let error):
            return "Failed to write settings: \(error.localizedDescription)"
        case .readFailed(let error):
            return "Failed to read settings: \(error.localizedDescription)"
        }
    }
}

struct ClaudeConfigService {
    static let configPath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/settings.json")

    static let defaultEndpoint = "http://localhost:4317"

    // Default environment variables
    static let defaultEnv: [String: String] = [
        "CLAUDE_CODE_ENABLE_TELEMETRY": "1",
        "OTEL_METRICS_EXPORTER": "otlp",
        "OTEL_LOGS_EXPORTER": "otlp",
        "OTEL_EXPORTER_OTLP_PROTOCOL": "grpc",
        "OTEL_EXPORTER_OTLP_ENDPOINT": "http://localhost:4317",
        "OTEL_METRIC_EXPORT_INTERVAL": "10000"
    ]

    static let systemKeys = Set(defaultEnv.keys)

    // MARK: - Telemetry Configuration
    static func isTelemetryEnabled() -> Bool {
        guard let config = try? loadConfig() else { return false }
        guard let env = config["env"] as? [String: String] else { return false }
        return env["CLAUDE_CODE_ENABLE_TELEMETRY"] == "1"
    }

    static func getOTelEndpoint() -> String {
        guard let config = try? loadConfig() else { return defaultEndpoint }
        guard let env = config["env"] as? [String: String] else { return defaultEndpoint }
        return env["OTEL_EXPORTER_OTLP_ENDPOINT"] ?? defaultEndpoint
    }

    static func enableTelemetry(endpoint: String? = nil) throws {
        var config = try loadConfig() ?? [:]

        var env = config["env"] as? [String: String] ?? [:]
        env["CLAUDE_CODE_ENABLE_TELEMETRY"] = "1"
        env["OTEL_METRICS_EXPORTER"] = "otlp"
        env["OTEL_LOGS_EXPORTER"] = "otlp"
        env["OTEL_EXPORTER_OTLP_PROTOCOL"] = "grpc"
        env["OTEL_EXPORTER_OTLP_ENDPOINT"] = endpoint ?? defaultEndpoint
        env["OTEL_METRIC_EXPORT_INTERVAL"] = "10000"

        config["env"] = env
        try saveConfig(config)
    }

    static func updateEndpoint(_ endpoint: String) throws {
        var config = try loadConfig() ?? [:]
        var env = config["env"] as? [String: String] ?? [:]
        env["OTEL_EXPORTER_OTLP_ENDPOINT"] = endpoint
        config["env"] = env
        try saveConfig(config)
    }

    static func disableTelemetry() throws {
        var config = try loadConfig() ?? [:]

        if var env = config["env"] as? [String: String] {
            env.removeValue(forKey: "CLAUDE_CODE_ENABLE_TELEMETRY")
            env.removeValue(forKey: "OTEL_METRICS_EXPORTER")
            env.removeValue(forKey: "OTEL_LOGS_EXPORTER")
            env.removeValue(forKey: "OTEL_EXPORTER_OTLP_PROTOCOL")
            env.removeValue(forKey: "OTEL_EXPORTER_OTLP_ENDPOINT")
            env.removeValue(forKey: "OTEL_METRIC_EXPORT_INTERVAL")

            if env.isEmpty {
                config.removeValue(forKey: "env")
            } else {
                config["env"] = env
            }
        }

        try saveConfig(config)
    }

    // MARK: - Config File Operations
    static func loadConfig() throws -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: configPath)
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ClaudeConfigError.invalidJSON
            }
            return json
        } catch let error as ClaudeConfigError {
            throw error
        } catch {
            throw ClaudeConfigError.readFailed(error)
        }
    }

    static func saveConfig(_ config: [String: Any]) throws {
        do {
            let data = try JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: configPath)
        } catch {
            throw ClaudeConfigError.writeFailed(error)
        }
    }

    // MARK: - Full Environment Management
    static func getAllEnv() -> [String: String] {
        guard let config = try? loadConfig() else { return [:] }
        return config["env"] as? [String: String] ?? [:]
    }

    static func saveAllEnv(_ env: [String: String]) throws {
        var config = try loadConfig() ?? [:]
        config["env"] = env
        try saveConfig(config)
    }

    // MARK: - Helpers
    static func configExists() -> Bool {
        FileManager.default.fileExists(atPath: configPath.path)
    }

    static func getConfigPath() -> String {
        configPath.path
    }
}
