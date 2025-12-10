import Foundation

enum APIError: LocalizedError {
    case invalidAPIKey
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "Invalid or missing Admin API Key"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

actor AnthropicAPIClient {
    private let baseURL = "https://api.anthropic.com/v1"
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - Usage Report
    func fetchUsageReport(
        apiKey: String,
        startDate: Date,
        endDate: Date
    ) async throws -> UsageReportResponse {
        guard !apiKey.isEmpty else {
            throw APIError.invalidAPIKey
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "\(baseURL)/organizations/usage_report/messages")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: startDate)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: endDate)),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await performRequest(request)
    }

    // MARK: - Cost Report
    func fetchCostReport(
        apiKey: String,
        startDate: Date,
        endDate: Date
    ) async throws -> CostReportResponse {
        guard !apiKey.isEmpty else {
            throw APIError.invalidAPIKey
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        var components = URLComponents(string: "\(baseURL)/organizations/cost_report")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: startDate)),
            URLQueryItem(name: "ending_at", value: formatter.string(from: endDate)),
            URLQueryItem(name: "bucket_width", value: "1d")
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await performRequest(request)
    }

    // MARK: - Claude Code Usage Report (daily aggregation)
    func fetchClaudeCodeUsage(
        apiKey: String,
        date: Date
    ) async throws -> ClaudeCodeUsageResponse {
        guard !apiKey.isEmpty else {
            throw APIError.invalidAPIKey
        }

        // Claude Code API requires YYYY-MM-DD format, returns single day
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")

        var components = URLComponents(string: "\(baseURL)/organizations/usage_report/claude_code")!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: formatter.string(from: date))
        ]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        return try await performRequest(request)
    }

    // MARK: - Private
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)

        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.httpError(httpResponse.statusCode, message)
        }

        // Debug: print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("API Response: \(jsonString)")
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw APIError.decodingError(error)
        }
    }
}
