import Foundation

enum DockerStatus {
    case running
    case stopped
    case notInstalled
    case unknown
}

struct DockerService {
    static let claudeUsagePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude-usage")
    static let containerName = "claude-otel-collector"

    // MARK: - Docker Status
    static func isDockerInstalled() -> Bool {
        let result = runCommand("which", arguments: ["docker"])
        return result.exitCode == 0 && !result.output.isEmpty
    }

    static func isDockerRunning() -> Bool {
        let result = runCommand("docker", arguments: ["info"])
        return result.exitCode == 0
    }

    static func getContainerStatus() -> DockerStatus {
        guard isDockerInstalled() else { return .notInstalled }
        guard isDockerRunning() else { return .stopped }

        let result = runCommand("docker", arguments: ["ps", "-q", "-f", "name=\(containerName)"])
        if result.exitCode == 0 && !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .running
        }

        return .stopped
    }

    // MARK: - Container Operations
    static func startContainer() -> (success: Bool, message: String) {
        guard isDockerRunning() else {
            return (false, "Docker is not running. Please start Docker Desktop first.")
        }

        // Check if config files exist
        let configPath = claudeUsagePath.appendingPathComponent("docker-compose.yaml")
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            return (false, "Docker compose file not found at \(configPath.path)")
        }

        let result = runCommand("docker-compose", arguments: ["-f", configPath.path, "up", "-d"])

        if result.exitCode == 0 {
            return (true, "Container started successfully")
        } else {
            return (false, "Failed to start container: \(result.output)")
        }
    }

    static func stopContainer() -> (success: Bool, message: String) {
        let configPath = claudeUsagePath.appendingPathComponent("docker-compose.yaml")

        let result = runCommand("docker-compose", arguments: ["-f", configPath.path, "down"])

        if result.exitCode == 0 {
            return (true, "Container stopped successfully")
        } else {
            return (false, "Failed to stop container: \(result.output)")
        }
    }

    static func restartContainer() -> (success: Bool, message: String) {
        let configPath = claudeUsagePath.appendingPathComponent("docker-compose.yaml")

        let result = runCommand("docker-compose", arguments: ["-f", configPath.path, "restart"])

        if result.exitCode == 0 {
            return (true, "Container restarted successfully")
        } else {
            return (false, "Failed to restart container: \(result.output)")
        }
    }

    // MARK: - Setup
    static func isSetupComplete() -> Bool {
        let configPath = claudeUsagePath.appendingPathComponent("docker-compose.yaml")
        let otelConfigPath = claudeUsagePath.appendingPathComponent("otel-config.yaml")

        return FileManager.default.fileExists(atPath: configPath.path) &&
               FileManager.default.fileExists(atPath: otelConfigPath.path)
    }

    static func getMetricsFilePath() -> URL {
        claudeUsagePath.appendingPathComponent("data/metrics.json")
    }

    static func getLogsFilePath() -> URL {
        claudeUsagePath.appendingPathComponent("data/logs.json")
    }

    // MARK: - Private Helpers
    private static func runCommand(_ command: String, arguments: [String]) -> (exitCode: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return (process.terminationStatus, output)
        } catch {
            return (-1, error.localizedDescription)
        }
    }
}
