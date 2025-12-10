import Foundation

// MARK: - Prometheus API Response Models
struct PrometheusResponse<T: Decodable>: Decodable {
    let status: String
    let data: T?
    let errorType: String?
    let error: String?
}

struct PrometheusQueryResult: Decodable {
    let resultType: String
    let result: [PrometheusMetric]
}

struct PrometheusMetric: Decodable {
    let metric: [String: String]
    let value: [PrometheusValue]?
    let values: [[PrometheusValue]]?

    enum CodingKeys: String, CodingKey {
        case metric, value, values
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        metric = try container.decode([String: String].self, forKey: .metric)

        // value is [timestamp, "string_value"]
        if let rawValue = try? container.decode([AnyCodableValue].self, forKey: .value) {
            value = rawValue.map { PrometheusValue(from: $0) }
        } else {
            value = nil
        }

        // values is [[timestamp, "string_value"], ...]
        if let rawValues = try? container.decode([[AnyCodableValue]].self, forKey: .values) {
            values = rawValues.map { $0.map { PrometheusValue(from: $0) } }
        } else {
            values = nil
        }
    }
}

enum PrometheusValue {
    case timestamp(Double)
    case stringValue(String)

    init(from value: AnyCodableValue) {
        switch value {
        case .double(let d):
            self = .timestamp(d)
        case .string(let s):
            self = .stringValue(s)
        case .int(let i):
            self = .timestamp(Double(i))
        }
    }

    var doubleValue: Double? {
        switch self {
        case .timestamp(let d):
            return d
        case .stringValue(let s):
            return Double(s)
        }
    }
}

enum AnyCodableValue: Decodable {
    case double(Double)
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            self = .double(d)
        } else if let i = try? container.decode(Int.self) {
            self = .int(i)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else {
            throw DecodingError.typeMismatch(AnyCodableValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown type"))
        }
    }
}

// MARK: - Prometheus Service
class PrometheusService {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        self.session = URLSession(configuration: config)
    }

    convenience init(host: String, port: Int) {
        let url = URL(string: "http://\(host):\(port)")!
        self.init(baseURL: url)
    }

    // MARK: - Health Check
    func checkConnection() async -> Bool {
        let url = baseURL.appendingPathComponent("/-/healthy")
        do {
            let (_, response) = try await session.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return httpResponse.statusCode == 200
            }
            return false
        } catch {
            return false
        }
    }

    // MARK: - Instant Query
    func query(_ promQL: String, time: Date? = nil) async throws -> [PrometheusMetric] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/query"), resolvingAgainstBaseURL: false)!

        var queryItems = [URLQueryItem(name: "query", value: promQL)]
        if let time = time {
            queryItems.append(URLQueryItem(name: "time", value: String(time.timeIntervalSince1970)))
        }
        components.queryItems = queryItems

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(PrometheusResponse<PrometheusQueryResult>.self, from: data)

        guard response.status == "success", let result = response.data else {
            throw PrometheusError.queryFailed(response.error ?? "Unknown error")
        }

        return result.result
    }

    // MARK: - Range Query
    func queryRange(_ promQL: String, start: Date, end: Date, step: TimeInterval) async throws -> [PrometheusMetric] {
        var components = URLComponents(url: baseURL.appendingPathComponent("/api/v1/query_range"), resolvingAgainstBaseURL: false)!

        components.queryItems = [
            URLQueryItem(name: "query", value: promQL),
            URLQueryItem(name: "start", value: String(start.timeIntervalSince1970)),
            URLQueryItem(name: "end", value: String(end.timeIntervalSince1970)),
            URLQueryItem(name: "step", value: "\(Int(step))s")
        ]

        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(PrometheusResponse<PrometheusQueryResult>.self, from: data)

        guard response.status == "success", let result = response.data else {
            throw PrometheusError.queryFailed(response.error ?? "Unknown error")
        }

        return result.result
    }

    // MARK: - Claude Code Specific Queries

    /// Get total input tokens
    func getTotalInputTokens() async throws -> Double {
        let metrics = try await query("sum(claude_code_input_tokens_total)")
        return metrics.first?.value?.last?.doubleValue ?? 0
    }

    /// Get total output tokens
    func getTotalOutputTokens() async throws -> Double {
        let metrics = try await query("sum(claude_code_output_tokens_total)")
        return metrics.first?.value?.last?.doubleValue ?? 0
    }

    /// Get total API requests
    func getTotalApiRequests() async throws -> Double {
        let metrics = try await query("sum(claude_code_api_requests_total)")
        return metrics.first?.value?.last?.doubleValue ?? 0
    }

    /// Get metrics since a specific time
    func getMetricsSince(_ startDate: Date) async throws -> ClaudeMetrics {
        let now = Date()
        let startTimestamp = Int(startDate.timeIntervalSince1970)

        // Query for tokens since start date
        let inputTokensQuery = "sum(increase(claude_code_input_tokens_total[\(Int(now.timeIntervalSince(startDate)))s]))"
        let outputTokensQuery = "sum(increase(claude_code_output_tokens_total[\(Int(now.timeIntervalSince(startDate)))s]))"
        let apiRequestsQuery = "sum(increase(claude_code_api_requests_total[\(Int(now.timeIntervalSince(startDate)))s]))"

        async let inputTokens = query(inputTokensQuery)
        async let outputTokens = query(outputTokensQuery)
        async let apiRequests = query(apiRequestsQuery)

        let (input, output, requests) = try await (inputTokens, outputTokens, apiRequests)

        return ClaudeMetrics(
            inputTokens: Int(input.first?.value?.last?.doubleValue ?? 0),
            outputTokens: Int(output.first?.value?.last?.doubleValue ?? 0),
            apiRequests: Int(requests.first?.value?.last?.doubleValue ?? 0)
        )
    }

    /// Get hourly metrics for a time range
    func getHourlyMetrics(start: Date, end: Date) async throws -> [HourlyMetricData] {
        let step: TimeInterval = 3600 // 1 hour

        let inputQuery = "sum(increase(claude_code_input_tokens_total[1h]))"
        let outputQuery = "sum(increase(claude_code_output_tokens_total[1h]))"
        let apiRequestsQuery = "sum(increase(claude_code_api_requests_total[1h]))"

        async let inputMetrics = queryRange(inputQuery, start: start, end: end, step: step)
        async let outputMetrics = queryRange(outputQuery, start: start, end: end, step: step)
        async let apiMetrics = queryRange(apiRequestsQuery, start: start, end: end, step: step)

        let (inputs, outputs, apis) = try await (inputMetrics, outputMetrics, apiMetrics)

        var hourlyData: [HourlyMetricData] = []

        // Combine results by timestamp
        if let inputValues = inputs.first?.values {
            for (index, values) in inputValues.enumerated() {
                guard values.count >= 2,
                      let timestamp = values[0].doubleValue,
                      let inputValue = values[1].doubleValue else { continue }

                let outputValue = outputs.first?.values?[safe: index]?[safe: 1]?.doubleValue ?? 0
                let apiValue = apis.first?.values?[safe: index]?[safe: 1]?.doubleValue ?? 0

                hourlyData.append(HourlyMetricData(
                    timestamp: Date(timeIntervalSince1970: timestamp),
                    inputTokens: Int(inputValue),
                    outputTokens: Int(outputValue),
                    apiRequests: Int(apiValue)
                ))
            }
        }

        return hourlyData
    }
}

// MARK: - Data Models
struct ClaudeMetrics {
    let inputTokens: Int
    let outputTokens: Int
    let apiRequests: Int

    var totalTokens: Int { inputTokens + outputTokens }
}

struct HourlyMetricData: Identifiable {
    let id = UUID()
    let timestamp: Date
    let inputTokens: Int
    let outputTokens: Int
    let apiRequests: Int

    var hour: Date { timestamp }
    var totalTokens: Int { inputTokens + outputTokens }
    var apiRequestCount: Int { apiRequests }

    var totalCost: Double {
        // Claude 3.5 Sonnet: $3 per 1M input, $15 per 1M output
        let inputCost = Double(inputTokens) / 1_000_000 * 3.0
        let outputCost = Double(outputTokens) / 1_000_000 * 15.0
        return inputCost + outputCost
    }
}

// MARK: - Errors
enum PrometheusError: LocalizedError {
    case queryFailed(String)
    case connectionFailed
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .queryFailed(let message):
            return "Query failed: \(message)"
        case .connectionFailed:
            return "Failed to connect to Prometheus"
        case .invalidResponse:
            return "Invalid response from Prometheus"
        }
    }
}

// MARK: - Array Safe Subscript
extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
