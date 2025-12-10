import Foundation

// MARK: - OTel Metric Models
struct OTelMetricRecord: Codable {
    let resourceMetrics: [ResourceMetric]?
}

struct ResourceMetric: Codable {
    let resource: Resource?
    let scopeMetrics: [ScopeMetric]?
}

struct Resource: Codable {
    let attributes: [Attribute]?
}

struct Attribute: Codable {
    let key: String
    let value: AttributeValue
}

struct AttributeValue: Codable {
    let stringValue: String?
    let intValue: String?
    let doubleValue: Double?
}

struct ScopeMetric: Codable {
    let scope: Scope?
    let metrics: [Metric]?
}

struct Scope: Codable {
    let name: String?
    let version: String?
}

struct Metric: Codable {
    let name: String
    let description: String?
    let unit: String?
    let sum: MetricSum?
    let gauge: MetricGauge?
}

struct MetricSum: Codable {
    let dataPoints: [DataPoint]?
    let aggregationTemporality: Int?
    let isMonotonic: Bool?
}

struct MetricGauge: Codable {
    let dataPoints: [DataPoint]?
}

struct DataPoint: Codable {
    let attributes: [Attribute]?
    let startTimeUnixNano: String?
    let timeUnixNano: String?
    let asInt: String?
    let asDouble: Double?
}

// MARK: - OTel Log Models
struct OTelLogRecord: Codable {
    let resourceLogs: [ResourceLog]?
}

struct ResourceLog: Codable {
    let resource: Resource?
    let scopeLogs: [ScopeLog]?
}

struct ScopeLog: Codable {
    let scope: Scope?
    let logRecords: [LogRecord]?
}

struct LogRecord: Codable {
    let timeUnixNano: String?
    let observedTimeUnixNano: String?
    let severityNumber: Int?
    let severityText: String?
    let body: LogBody?
    let attributes: [Attribute]?
}

struct LogBody: Codable {
    let stringValue: String?
}

// MARK: - Aggregated Metrics
struct AggregatedMetrics {
    var totalCost: Double = 0
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var sessionCount: Int = 0
    var activeTimeSeconds: Int = 0
    var linesOfCode: Int = 0
    var commitCount: Int = 0
    var prCount: Int = 0
    var promptCount: Int = 0       // claude_code.user_prompt events
    var apiRequestCount: Int = 0   // claude_code.api_request events
    var lastUpdated: Date?
}

// MARK: - Hourly Metrics
struct HourlyMetric: Identifiable {
    let id = UUID()
    let hour: Date
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var totalCost: Double = 0
    var sessionCount: Int = 0
    var apiRequestCount: Int = 0
    var activeTimeSeconds: Int = 0

    var totalTokens: Int {
        inputTokens + outputTokens
    }

    var activeTimeFormatted: String {
        if activeTimeSeconds < 60 { return "\(activeTimeSeconds)s" }
        if activeTimeSeconds < 3600 { return "\(activeTimeSeconds / 60)m" }
        return "\(activeTimeSeconds / 3600)h \((activeTimeSeconds % 3600) / 60)m"
    }
}

// MARK: - Metrics File Reader
class MetricsFileReader {
    private let metricsPath: URL
    private let logsPath: URL

    init(metricsPath: URL? = nil, logsPath: URL? = nil) {
        self.metricsPath = metricsPath ?? DockerService.getMetricsFilePath()
        self.logsPath = logsPath ?? DockerService.getLogsFilePath()
    }

    // MARK: - Read Metrics
    func readMetrics(since startDate: Date? = nil) -> AggregatedMetrics {
        var aggregated = AggregatedMetrics()

        guard FileManager.default.fileExists(atPath: metricsPath.path) else {
            return aggregated
        }

        do {
            let data = try Data(contentsOf: metricsPath)

            // Try parsing as single JSON object first (default file exporter format)
            if let record = try? JSONDecoder().decode(OTelMetricRecord.self, from: data) {
                processRecord(record, into: &aggregated, since: startDate)
            } else {
                // Fall back to NDJSON format (line-delimited)
                let content = String(data: data, encoding: .utf8) ?? ""
                let lines = content.components(separatedBy: .newlines)

                for line in lines where !line.isEmpty {
                    if let lineData = line.data(using: .utf8),
                       let record = try? JSONDecoder().decode(OTelMetricRecord.self, from: lineData) {
                        processRecord(record, into: &aggregated, since: startDate)
                    }
                }
            }

            aggregated.lastUpdated = getFileModificationDate()

        } catch {
            print("Error reading metrics file: \(error)")
        }

        // Also read logs for event counts
        readLogs(into: &aggregated, since: startDate)

        return aggregated
    }

    // MARK: - Read Logs
    private func readLogs(into aggregated: inout AggregatedMetrics, since startDate: Date?) {
        guard FileManager.default.fileExists(atPath: logsPath.path) else {
            return
        }

        do {
            let data = try Data(contentsOf: logsPath)

            // Try parsing as single JSON object first
            if let record = try? JSONDecoder().decode(OTelLogRecord.self, from: data) {
                processLogRecord(record, into: &aggregated, since: startDate)
            } else {
                // Fall back to NDJSON format (line-delimited)
                let content = String(data: data, encoding: .utf8) ?? ""
                let lines = content.components(separatedBy: .newlines)

                for line in lines where !line.isEmpty {
                    if let lineData = line.data(using: .utf8),
                       let record = try? JSONDecoder().decode(OTelLogRecord.self, from: lineData) {
                        processLogRecord(record, into: &aggregated, since: startDate)
                    }
                }
            }
        } catch {
            print("Error reading logs file: \(error)")
        }
    }

    private func processLogRecord(_ record: OTelLogRecord, into aggregated: inout AggregatedMetrics, since startDate: Date?) {
        guard let resourceLogs = record.resourceLogs else { return }

        for resourceLog in resourceLogs {
            guard let scopeLogs = resourceLog.scopeLogs else { continue }

            for scopeLog in scopeLogs {
                guard let logRecords = scopeLog.logRecords else { continue }

                for logRecord in logRecords {
                    processLogEntry(logRecord, into: &aggregated, since: startDate)
                }
            }
        }
    }

    private func processLogEntry(_ logRecord: LogRecord, into aggregated: inout AggregatedMetrics, since startDate: Date?) {
        // Check if log is within date range
        if let startDate = startDate,
           let timeNano = logRecord.timeUnixNano ?? logRecord.observedTimeUnixNano,
           let nanoValue = Double(timeNano) {
            let date = Date(timeIntervalSince1970: nanoValue / 1_000_000_000)
            if date < startDate {
                return
            }
        }

        // Get event name from body or attributes
        let eventName = logRecord.body?.stringValue ?? getLogAttribute(from: logRecord, key: "event.name")

        switch eventName {
        case "claude_code.user_prompt":
            aggregated.promptCount += 1
        case "claude_code.api_request":
            aggregated.apiRequestCount += 1
        default:
            break
        }
    }

    private func getLogAttribute(from logRecord: LogRecord, key: String) -> String? {
        logRecord.attributes?.first(where: { $0.key == key })?.value.stringValue
    }

    // MARK: - Process Records
    private func processRecord(_ record: OTelMetricRecord, into aggregated: inout AggregatedMetrics, since startDate: Date?) {
        guard let resourceMetrics = record.resourceMetrics else { return }

        for resourceMetric in resourceMetrics {
            guard let scopeMetrics = resourceMetric.scopeMetrics else { continue }

            for scopeMetric in scopeMetrics {
                guard let metrics = scopeMetric.metrics else { continue }

                for metric in metrics {
                    processMetric(metric, into: &aggregated, since: startDate)
                }
            }
        }
    }

    private func processMetric(_ metric: Metric, into aggregated: inout AggregatedMetrics, since startDate: Date?) {
        let dataPoints = metric.sum?.dataPoints ?? metric.gauge?.dataPoints ?? []

        for dataPoint in dataPoints {
            // Check if data point is within date range
            if let startDate = startDate,
               let timeNano = dataPoint.timeUnixNano,
               let nanoValue = Double(timeNano) {
                let date = Date(timeIntervalSince1970: nanoValue / 1_000_000_000)
                if date < startDate {
                    continue
                }
            }

            let value = dataPoint.asDouble ?? (dataPoint.asInt.flatMap { Double($0) } ?? 0)

            switch metric.name {
            case "claude_code.cost.usage":
                aggregated.totalCost += value

            case "claude_code.token.usage":
                if let tokenType = getAttribute(from: dataPoint, key: "token_type") {
                    if tokenType == "input" {
                        aggregated.inputTokens += Int(value)
                    } else if tokenType == "output" {
                        aggregated.outputTokens += Int(value)
                    }
                } else {
                    // Default: assume total tokens
                    aggregated.inputTokens += Int(value)
                }

            case "claude_code.session.count":
                aggregated.sessionCount += Int(value)

            case "claude_code.active_time.total":
                aggregated.activeTimeSeconds += Int(value)

            case "claude_code.lines_of_code.count":
                aggregated.linesOfCode += Int(value)

            case "claude_code.commit.count":
                aggregated.commitCount += Int(value)

            case "claude_code.pull_request.count":
                aggregated.prCount += Int(value)

            default:
                break
            }
        }
    }

    private func getAttribute(from dataPoint: DataPoint, key: String) -> String? {
        dataPoint.attributes?.first(where: { $0.key == key })?.value.stringValue
    }

    // MARK: - File Info
    func getFileModificationDate() -> Date? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: metricsPath.path),
              let modDate = attributes[.modificationDate] as? Date else {
            return nil
        }
        return modDate
    }

    func metricsFileExists() -> Bool {
        FileManager.default.fileExists(atPath: metricsPath.path)
    }

    // MARK: - Hourly Metrics
    func readHourlyMetrics(hours: Int = 24) -> [HourlyMetric] {
        var hourlyData: [Date: HourlyMetric] = [:]
        let calendar = Calendar.current
        let now = Date()
        let startDate = calendar.date(byAdding: .hour, value: -hours, to: now) ?? now

        // Read metrics
        if FileManager.default.fileExists(atPath: metricsPath.path) {
            do {
                let data = try Data(contentsOf: metricsPath)

                if let record = try? JSONDecoder().decode(OTelMetricRecord.self, from: data) {
                    processRecordForHourly(record, into: &hourlyData, since: startDate, calendar: calendar)
                } else {
                    let content = String(data: data, encoding: .utf8) ?? ""
                    let lines = content.components(separatedBy: .newlines)

                    for line in lines where !line.isEmpty {
                        if let lineData = line.data(using: .utf8),
                           let record = try? JSONDecoder().decode(OTelMetricRecord.self, from: lineData) {
                            processRecordForHourly(record, into: &hourlyData, since: startDate, calendar: calendar)
                        }
                    }
                }
            } catch {
                print("Error reading metrics file: \(error)")
            }
        }

        // Read logs for API request counts
        readLogsForHourly(into: &hourlyData, since: startDate, calendar: calendar)

        return hourlyData.values.sorted { $0.hour < $1.hour }
    }

    private func readLogsForHourly(into hourlyData: inout [Date: HourlyMetric], since startDate: Date, calendar: Calendar) {
        guard FileManager.default.fileExists(atPath: logsPath.path) else { return }

        do {
            let data = try Data(contentsOf: logsPath)

            if let record = try? JSONDecoder().decode(OTelLogRecord.self, from: data) {
                processLogRecordForHourly(record, into: &hourlyData, since: startDate, calendar: calendar)
            } else {
                let content = String(data: data, encoding: .utf8) ?? ""
                let lines = content.components(separatedBy: .newlines)

                for line in lines where !line.isEmpty {
                    if let lineData = line.data(using: .utf8),
                       let record = try? JSONDecoder().decode(OTelLogRecord.self, from: lineData) {
                        processLogRecordForHourly(record, into: &hourlyData, since: startDate, calendar: calendar)
                    }
                }
            }
        } catch {
            print("Error reading logs file: \(error)")
        }
    }

    private func processLogRecordForHourly(_ record: OTelLogRecord, into hourlyData: inout [Date: HourlyMetric], since startDate: Date, calendar: Calendar) {
        guard let resourceLogs = record.resourceLogs else { return }

        for resourceLog in resourceLogs {
            guard let scopeLogs = resourceLog.scopeLogs else { continue }

            for scopeLog in scopeLogs {
                guard let logRecords = scopeLog.logRecords else { continue }

                for logRecord in logRecords {
                    guard let timeNano = logRecord.timeUnixNano ?? logRecord.observedTimeUnixNano,
                          let nanoValue = Double(timeNano) else { continue }

                    let date = Date(timeIntervalSince1970: nanoValue / 1_000_000_000)
                    guard date >= startDate else { continue }

                    let eventName = logRecord.body?.stringValue ?? getLogAttribute(from: logRecord, key: "event.name")
                    guard eventName == "claude_code.api_request" else { continue }

                    let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date

                    if hourlyData[hourStart] == nil {
                        hourlyData[hourStart] = HourlyMetric(hour: hourStart)
                    }

                    hourlyData[hourStart]?.apiRequestCount += 1
                }
            }
        }
    }

    private func processRecordForHourly(_ record: OTelMetricRecord, into hourlyData: inout [Date: HourlyMetric], since startDate: Date, calendar: Calendar) {
        guard let resourceMetrics = record.resourceMetrics else { return }

        for resourceMetric in resourceMetrics {
            guard let scopeMetrics = resourceMetric.scopeMetrics else { continue }

            for scopeMetric in scopeMetrics {
                guard let metrics = scopeMetric.metrics else { continue }

                for metric in metrics {
                    processMetricForHourly(metric, into: &hourlyData, since: startDate, calendar: calendar)
                }
            }
        }
    }

    private func processMetricForHourly(_ metric: Metric, into hourlyData: inout [Date: HourlyMetric], since startDate: Date, calendar: Calendar) {
        let dataPoints = metric.sum?.dataPoints ?? metric.gauge?.dataPoints ?? []

        for dataPoint in dataPoints {
            guard let timeNano = dataPoint.timeUnixNano,
                  let nanoValue = Double(timeNano) else { continue }

            let date = Date(timeIntervalSince1970: nanoValue / 1_000_000_000)
            guard date >= startDate else { continue }

            // Round to hour
            let hourStart = calendar.dateInterval(of: .hour, for: date)?.start ?? date

            if hourlyData[hourStart] == nil {
                hourlyData[hourStart] = HourlyMetric(hour: hourStart)
            }

            let value = dataPoint.asDouble ?? (dataPoint.asInt.flatMap { Double($0) } ?? 0)

            switch metric.name {
            case "claude_code.cost.usage":
                hourlyData[hourStart]?.totalCost += value

            case "claude_code.token.usage":
                if let tokenType = getAttribute(from: dataPoint, key: "token_type") {
                    if tokenType == "input" {
                        hourlyData[hourStart]?.inputTokens += Int(value)
                    } else if tokenType == "output" {
                        hourlyData[hourStart]?.outputTokens += Int(value)
                    }
                } else {
                    hourlyData[hourStart]?.inputTokens += Int(value)
                }

            case "claude_code.session.count":
                hourlyData[hourStart]?.sessionCount += Int(value)

            case "claude_code.active_time.total":
                hourlyData[hourStart]?.activeTimeSeconds += Int(value)

            default:
                break
            }
        }
    }
}
