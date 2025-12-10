import Foundation
import SwiftUI
import Combine

@MainActor
class UsageViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var isLoading = false
    @Published var error: String?
    @Published var lastUpdated: Date?
    @Published var isConnected = false

    // MARK: - Metrics
    @Published var localMetrics: AggregatedMetrics = AggregatedMetrics()
    @Published var currentSessionMetrics: AggregatedMetrics = AggregatedMetrics()

    // MARK: - Settings
    @AppStorage("refreshIntervalSeconds") var refreshInterval: Int = 60
    @AppStorage("maxSessionApiRequests") var maxSessionApiRequests: Int = 500
    @AppStorage("sessionWindowHours") var sessionWindowHours: Int = 5
    @AppStorage("sessionStartTimestamp") private var sessionStartTimestamp: Double = 0
    @AppStorage("prometheusHost") var prometheusHost: String = "localhost"
    @AppStorage("prometheusPort") var prometheusPort: Int = 9090

    // MARK: - Weekly Period (KST Tuesday 08:00)
    var weeklyPeriod: (start: Date, end: Date) {
        calculateWeeklyPeriod()
    }

    var weeklyPeriodFormatted: String {
        let period = weeklyPeriod
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return "\(formatter.string(from: period.start)) ~ \(formatter.string(from: period.end))"
    }

    // MARK: - Current Session (Rolling window)
    var currentSessionPeriod: (start: Date, end: Date) {
        let now = Date()
        let start = sessionStartDate
        return (start, now)
    }

    var sessionStartDate: Date {
        let now = Date()
        let maxWindowSeconds = Double(sessionWindowHours) * 3600

        if sessionStartTimestamp == 0 {
            return now.addingTimeInterval(-maxWindowSeconds)
        }

        let startDate = Date(timeIntervalSince1970: sessionStartTimestamp)
        let elapsed = now.timeIntervalSince(startDate)

        if elapsed > maxWindowSeconds {
            return now.addingTimeInterval(-maxWindowSeconds)
        }

        return startDate
    }

    var currentSessionPeriodFormatted: String {
        let period = currentSessionPeriod
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        formatter.timeZone = TimeZone(identifier: "Asia/Seoul")
        return "\(formatter.string(from: period.start)) ~ now"
    }

    func resetSession() {
        sessionStartTimestamp = Date().timeIntervalSince1970
        Task {
            await refresh()
        }
    }

    func setSessionStartTime(_ date: Date) {
        sessionStartTimestamp = date.timeIntervalSince1970
        Task {
            await refresh()
        }
    }

    var currentSessionTotalTokens: Int {
        currentSessionMetrics.inputTokens + currentSessionMetrics.outputTokens
    }

    var currentSessionPromptCount: Int {
        currentSessionMetrics.promptCount
    }

    var currentSessionApiRequestCount: Int {
        currentSessionMetrics.apiRequestCount
    }

    var currentSessionUsagePercent: Double {
        guard maxSessionApiRequests > 0 else { return 0 }
        return min(Double(currentSessionApiRequestCount) / Double(maxSessionApiRequests) * 100, 100)
    }

    // MARK: - Computed Properties
    var hasMetrics: Bool {
        localMetrics.totalCost > 0 || localMetrics.inputTokens > 0 || localMetrics.sessionCount > 0
    }

    var todayCost: Double? {
        localMetrics.totalCost > 0 ? localMetrics.totalCost : nil
    }

    var claudeCodeTotalCost: Double {
        localMetrics.totalCost
    }

    var claudeCodeTotalTokens: (input: Int, output: Int) {
        (localMetrics.inputTokens, localMetrics.outputTokens)
    }

    var sessionCount: Int {
        localMetrics.sessionCount
    }

    var activeTimeFormatted: String {
        let seconds = localMetrics.activeTimeSeconds
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3600 { return "\(seconds / 60)m" }
        return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
    }

    var linesOfCode: Int {
        localMetrics.linesOfCode
    }

    var commitCount: Int {
        localMetrics.commitCount
    }

    var promptCount: Int {
        localMetrics.promptCount
    }

    var apiRequestCount: Int {
        localMetrics.apiRequestCount
    }

    var timeSinceLastUpdate: String {
        guard let lastUpdated else { return "Never" }
        let interval = Date().timeIntervalSince(lastUpdated)

        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min ago"
        } else {
            let hours = Int(interval / 3600)
            return "\(hours) hr ago"
        }
    }

    var prometheusEndpoint: String {
        "http://\(prometheusHost):\(prometheusPort)"
    }

    // MARK: - Private
    private var prometheusService: PrometheusService?
    private var refreshTimer: Timer?

    // MARK: - Init
    init() {
        updatePrometheusService()
        setupAutoRefresh()

        Task {
            await refresh()
        }
    }

    // MARK: - Public Methods
    func updatePrometheusService() {
        prometheusService = PrometheusService(host: prometheusHost, port: prometheusPort)
    }

    func checkConnection() async -> Bool {
        guard let service = prometheusService else { return false }
        let connected = await service.checkConnection()
        isConnected = connected
        return connected
    }

    func refresh() async {
        isLoading = true
        error = nil

        // Check connection first
        let connected = await checkConnection()

        guard connected, let service = prometheusService else {
            error = "Cannot connect to Prometheus at \(prometheusEndpoint)"
            isLoading = false
            return
        }

        do {
            // Fetch weekly metrics
            let period = weeklyPeriod
            let weeklyMetrics = try await service.getMetricsSince(period.start)

            localMetrics = AggregatedMetrics(
                totalCost: calculateCost(input: weeklyMetrics.inputTokens, output: weeklyMetrics.outputTokens),
                inputTokens: weeklyMetrics.inputTokens,
                outputTokens: weeklyMetrics.outputTokens,
                sessionCount: 0,
                activeTimeSeconds: 0,
                linesOfCode: 0,
                commitCount: 0,
                promptCount: 0,
                apiRequestCount: weeklyMetrics.apiRequests,
                lastUpdated: Date()
            )

            // Fetch current session metrics
            let sessionPeriod = currentSessionPeriod
            let sessionMetrics = try await service.getMetricsSince(sessionPeriod.start)

            currentSessionMetrics = AggregatedMetrics(
                totalCost: calculateCost(input: sessionMetrics.inputTokens, output: sessionMetrics.outputTokens),
                inputTokens: sessionMetrics.inputTokens,
                outputTokens: sessionMetrics.outputTokens,
                sessionCount: 0,
                activeTimeSeconds: 0,
                linesOfCode: 0,
                commitCount: 0,
                promptCount: 0,
                apiRequestCount: sessionMetrics.apiRequests,
                lastUpdated: Date()
            )

            lastUpdated = Date()

        } catch {
            self.error = "Failed to fetch metrics: \(error.localizedDescription)"
        }

        isLoading = false
    }

    // MARK: - Cost Calculation (Claude 3.5 Sonnet pricing)
    private func calculateCost(input: Int, output: Int) -> Double {
        // Claude 3.5 Sonnet: $3 per 1M input, $15 per 1M output
        let inputCost = Double(input) / 1_000_000 * 3.0
        let outputCost = Double(output) / 1_000_000 * 15.0
        return inputCost + outputCost
    }

    // MARK: - Weekly Period Calculation (KST Tuesday 08:00)
    private func calculateWeeklyPeriod() -> (start: Date, end: Date) {
        guard let kst = TimeZone(identifier: "Asia/Seoul") else {
            return (Date(), Date())
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = kst

        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let currentHour = calendar.component(.hour, from: now)

        var daysSinceTuesday = currentWeekday - 3
        if daysSinceTuesday < 0 {
            daysSinceTuesday += 7
        }

        if currentWeekday == 3 && currentHour < 8 {
            daysSinceTuesday = 7
        }

        guard let startOfDay = calendar.date(byAdding: .day, value: -daysSinceTuesday, to: now),
              let tuesdayStart = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: startOfDay) else {
            return (Date(), Date())
        }

        guard let tuesdayEnd = calendar.date(byAdding: .day, value: 7, to: tuesdayStart),
              let endTime = calendar.date(byAdding: .second, value: -1, to: tuesdayEnd) else {
            return (tuesdayStart, Date())
        }

        return (tuesdayStart, endTime)
    }

    // MARK: - Hourly Metrics
    func getHourlyMetrics(hours: Int) async -> [HourlyMetricData] {
        guard let service = prometheusService else { return [] }

        let end = Date()
        let start = end.addingTimeInterval(-Double(hours) * 3600)

        do {
            return try await service.getHourlyMetrics(start: start, end: end)
        } catch {
            return []
        }
    }

    // MARK: - Private Methods
    private func setupAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(refreshInterval), repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refresh()
            }
        }
    }
}
