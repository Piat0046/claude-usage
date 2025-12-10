import SwiftUI
import AppKit

struct SettingsView: View {
    @ObservedObject var viewModel: UsageViewModel
    @State private var telemetryEnabled = false
    @State private var otelEndpoint = ""
    @State private var statusMessage = ""
    @State private var hourlyMetrics: [HourlyMetricData] = []

    // Prometheus settings
    @State private var prometheusHost = ""
    @State private var prometheusPort = ""

    // Session time picker
    @State private var showTimePicker = false
    @State private var selectedSessionTime = Date()
    @State private var timePickerError = ""

    // Claude env editor
    @State private var showClaudeEnvEditor = false

    // Prometheus settings modal
    @State private var showPrometheusSettings = false

    // OTel settings modal
    @State private var showOTelSettings = false

    // Available metrics popover
    @State private var showAvailableMetrics = false

    // OTel Collector status
    @State private var otelCollectorConnected = false
    @AppStorage("otelHttpPort") private var otelHttpPort: Int = 4318

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            setupTab
                .tabItem {
                    Label("Setup", systemImage: "wrench.and.screwdriver")
                }

            metricTab
                .tabItem {
                    Label("Metric", systemImage: "chart.line.uptrend.xyaxis")
                }

            aboutTab
                .tabItem {
                    Label("About", systemImage: "info.circle")
                }
        }
        .frame(width: 500, height: 580)
        .sheet(isPresented: $showClaudeEnvEditor) {
            ClaudeEnvEditorView()
        }
        .sheet(isPresented: $showPrometheusSettings) {
            PrometheusSettingsView(
                host: $prometheusHost,
                port: $prometheusPort,
                onSave: {
                    applyPrometheusSettings()
                    Task {
                        await viewModel.refresh()
                    }
                }
            )
        }
        .sheet(isPresented: $showOTelSettings) {
            OTelSettingsView(
                endpoint: $otelEndpoint,
                httpPort: $otelHttpPort,
                onSave: { newEndpoint in
                    do {
                        try ClaudeConfigService.updateEndpoint(newEndpoint)
                        otelEndpoint = newEndpoint
                        statusMessage = "OTel endpoint updated. Restart Claude Code to apply."
                        Task {
                            await checkOTelCollectorConnection()
                        }
                    } catch {
                        statusMessage = "Failed: \(error.localizedDescription)"
                    }
                }
            )
        }
        .onAppear {
            refreshStatus()
            loadHourlyMetrics()
        }
    }

    // MARK: - General Tab
    private var generalTab: some View {
        Form {
            // Connection Status
            if !viewModel.isConnected || viewModel.error != nil {
                Section {
                    HStack {
                        Image(systemName: viewModel.isConnected ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(viewModel.isConnected ? .green : .orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.isConnected ? "Connected" : "Not Connected")
                                .font(.headline)
                            if let error = viewModel.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Button("Retry") {
                                Task { await viewModel.refresh() }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                } header: {
                    Text("Status")
                }
            }

            // Current Session (6-hour block)
            Section {
                HStack {
                    Label("Period", systemImage: "clock")
                    Spacer()
                    Text(viewModel.currentSessionPeriodFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: {
                        selectedSessionTime = viewModel.sessionStartDate
                        timePickerError = ""
                        showTimePicker.toggle()
                    }) {
                        Image(systemName: "clock.badge.questionmark")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showTimePicker, arrowEdge: .trailing) {
                        sessionTimePickerView
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("API Requests", systemImage: "arrow.up.arrow.down.circle")
                        Spacer()
                        Text("\(viewModel.currentSessionApiRequestCount) / \(viewModel.maxSessionApiRequests)")
                            .fontWeight(.semibold)
                        Text("(\(Int(viewModel.currentSessionUsagePercent))%)")
                            .foregroundColor(sessionUsageColor)
                            .fontWeight(.medium)
                    }

                    // Progress Bar
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.2))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(sessionUsageColor)
                                .frame(width: geometry.size.width * (viewModel.currentSessionUsagePercent / 100), height: 8)
                        }
                    }
                    .frame(height: 8)
                }

                HStack {
                    Label("Prompts", systemImage: "text.bubble")
                    Spacer()
                    Text("\(viewModel.currentSessionPromptCount)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Tokens", systemImage: "number")
                    Spacer()
                    Text(formatTokens(viewModel.currentSessionTotalTokens))
                        .foregroundColor(.secondary)
                }

                Button("Reset Session") {
                    viewModel.resetSession()
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Current Session")
            } footer: {
                Text("Rolling window from session start")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Weekly Period Info
            Section {
                HStack {
                    Label("Period", systemImage: "calendar")
                    Spacer()
                    Text(viewModel.weeklyPeriodFormatted)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Weekly Total (KST)")
            } footer: {
                Text("Tuesday 08:00 ~ next Tuesday 07:59")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Weekly Usage Statistics
            Section {
                HStack {
                    Label("Total Cost", systemImage: "dollarsign.circle")
                    Spacer()
                    Text(viewModel.claudeCodeTotalCost.formatted(.currency(code: "USD")))
                        .fontWeight(.semibold)
                }

                HStack {
                    Label("Tokens", systemImage: "number")
                    Spacer()
                    Text(formatTokens(viewModel.claudeCodeTotalTokens.input + viewModel.claudeCodeTotalTokens.output))
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Sessions", systemImage: "terminal")
                    Spacer()
                    Text("\(viewModel.sessionCount)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Active Time", systemImage: "clock")
                    Spacer()
                    Text(viewModel.activeTimeFormatted)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Lines of Code", systemImage: "text.alignleft")
                    Spacer()
                    Text("\(viewModel.linesOfCode)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Commits", systemImage: "arrow.triangle.branch")
                    Spacer()
                    Text("\(viewModel.commitCount)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("Prompts", systemImage: "text.bubble")
                    Spacer()
                    Text("\(viewModel.promptCount)")
                        .foregroundColor(.secondary)
                }

                HStack {
                    Label("API Requests", systemImage: "arrow.up.arrow.down.circle")
                    Spacer()
                    Text("\(viewModel.apiRequestCount)")
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Usage Statistics")
            }

            Section {
                LaunchAtLoginToggle()
            } header: {
                Text("System")
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var sessionUsageColor: Color {
        let percent = viewModel.currentSessionUsagePercent
        if percent >= 90 {
            return .red
        } else if percent >= 70 {
            return .orange
        } else {
            return .green
        }
    }

    private var sessionTimePickerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Set Session Start Time")
                .font(.headline)

            // Date picker (calendar)
            DatePicker(
                "Date",
                selection: $selectedSessionTime,
                displayedComponents: [.date]
            )
            .environment(\.locale, Locale(identifier: "ko_KR"))
            .datePickerStyle(.graphical)

            // Time picker (stepper field)
            HStack {
                Text("Time")
                    .frame(width: 50, alignment: .leading)
                DatePicker(
                    "",
                    selection: $selectedSessionTime,
                    displayedComponents: [.hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.stepperField)
            }

            if !timePickerError.isEmpty {
                Text(timePickerError)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack {
                Button("Cancel") {
                    showTimePicker = false
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Apply") {
                    applySessionTime()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 280)
    }

    private func applySessionTime() {
        let now = Date()
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        if selectedSessionTime > now {
            timePickerError = "Cannot set future time"
            return
        }

        if selectedSessionTime < fiveHoursAgo {
            timePickerError = "Cannot set more than 5 hours ago"
            return
        }

        timePickerError = ""
        viewModel.setSessionStartTime(selectedSessionTime)
        showTimePicker = false
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Setup Tab
    private var setupTab: some View {
        Form {
            // Session Settings Section
            Section {
                Picker("Max API Requests", selection: $viewModel.maxSessionApiRequests) {
                    Text("100").tag(100)
                    Text("200").tag(200)
                    Text("300").tag(300)
                    Text("500").tag(500)
                    Text("1000").tag(1000)
                }

                Picker("Window Size", selection: $viewModel.sessionWindowHours) {
                    Text("1 hour").tag(1)
                    Text("2 hours").tag(2)
                    Text("3 hours").tag(3)
                    Text("4 hours").tag(4)
                    Text("5 hours").tag(5)
                    Text("6 hours").tag(6)
                    Text("8 hours").tag(8)
                    Text("12 hours").tag(12)
                }
            } header: {
                Text("Session Settings")
            } footer: {
                Text("API request limit for percentage calculation")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Refresh Interval Section
            Section {
                Picker("Refresh Interval", selection: $viewModel.refreshInterval) {
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                    Text("30 minutes").tag(1800)
                }
            } header: {
                Text("Data Refresh")
            } footer: {
                Text("How often to read metrics from the local OTel collector")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // OTel Collector Connection (Claude Code → OTel)
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(otelCollectorConnected ? "Connected" : "Disconnected")
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(otelCollectorConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }

                HStack {
                    Text("gRPC Endpoint")
                    Spacer()
                    Text(otelEndpoint.isEmpty ? "Not configured" : otelEndpoint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack {
                    Text("HTTP Port")
                    Spacer()
                    Text("\(otelHttpPort)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button("Configure") {
                    showOTelSettings = true
                }
                .buttonStyle(.bordered)
            } header: {
                Text("OTel Collector")
            } footer: {
                Text("Claude Code sends telemetry via gRPC. HTTP port is used for status check.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Prometheus Connection (App → Prometheus)
            Section {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(viewModel.isConnected ? "Connected" : "Disconnected")
                        .foregroundColor(.secondary)
                    Circle()
                        .fill(viewModel.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }

                HStack {
                    Text("Endpoint")
                    Spacer()
                    Text(viewModel.prometheusEndpoint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("Configure") {
                        showPrometheusSettings = true
                    }
                    .buttonStyle(.bordered)

                    Button("View Metrics") {
                        Task {
                            await viewModel.fetchAvailableMetrics()
                        }
                        showAvailableMetrics = true
                    }
                    .buttonStyle(.bordered)
                    .popover(isPresented: $showAvailableMetrics) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Available Metrics")
                                    .font(.headline)
                                Spacer()
                                Text("\(viewModel.availableMetrics.count)")
                                    .foregroundColor(.secondary)
                            }
                            .padding(.bottom, 4)

                            Divider()

                            if viewModel.availableMetrics.isEmpty {
                                Text("No metrics found")
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 4) {
                                        ForEach(viewModel.availableMetrics, id: \.self) { metric in
                                            Text(metric)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                }
                                .frame(maxHeight: 200)
                            }
                        }
                        .padding()
                        .frame(width: 350)
                    }
                }
            } header: {
                Text("Prometheus")
            } footer: {
                Text("App queries metrics from Prometheus")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Claude Code Telemetry Section
            Section {
                HStack {
                    Text("Telemetry")
                    Spacer()
                    Text(telemetryEnabled ? "Enabled" : "Disabled")
                        .foregroundColor(telemetryEnabled ? .green : .secondary)
                }

                HStack(spacing: 12) {
                    Button("Edit Settings") {
                        showClaudeEnvEditor = true
                    }
                    .buttonStyle(.bordered)

                    Button("Open Config") {
                        let url = URL(fileURLWithPath: ClaudeConfigService.getConfigPath())
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button(telemetryEnabled ? "Disable Telemetry" : "Enable Telemetry") {
                        updateTelemetry(enable: !telemetryEnabled)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Claude Code Settings")
            } footer: {
                Label("Restart Claude Code after updating settings", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.orange)
            }

            // Status Message
            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundColor(statusMessage.contains("Failed") ? .red : .green)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Metric Tab
    private var metricTab: some View {
        Form {
            Section {
                if hourlyMetrics.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("No hourly data available")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                } else {
                    // Table Header
                    HStack {
                        Text("Time")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("API")
                            .frame(width: 45, alignment: .trailing)
                        Text("Tokens")
                            .frame(width: 65, alignment: .trailing)
                        Text("Cost")
                            .frame(width: 65, alignment: .trailing)
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)

                    ForEach(Array(hourlyMetrics.reversed())) { metric in
                        HStack {
                            Text(formatHour(metric.hour))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(metric.apiRequestCount)")
                                .frame(width: 45, alignment: .trailing)
                            Text(formatTokensShort(metric.totalTokens))
                                .frame(width: 65, alignment: .trailing)
                                .fontWeight(.medium)
                            Text(metric.totalCost.formatted(.currency(code: "USD")))
                                .frame(width: 65, alignment: .trailing)
                        }
                        .font(.caption)
                    }
                }
            } header: {
                HStack {
                    Text("Hourly Usage (Last 24h)")
                    Spacer()
                    Button(action: loadHourlyMetrics) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if !hourlyMetrics.isEmpty {
                Section {
                    HStack {
                        Label("API Requests", systemImage: "arrow.up.arrow.down.circle")
                        Spacer()
                        Text("\(hourlyMetrics.reduce(0) { $0 + $1.apiRequestCount })")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Tokens", systemImage: "number")
                        Spacer()
                        Text(formatTokensShort(hourlyMetrics.reduce(0) { $0 + $1.totalTokens }))
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Label("Total Cost", systemImage: "dollarsign.circle")
                        Spacer()
                        Text(hourlyMetrics.reduce(0.0) { $0 + $1.totalCost }.formatted(.currency(code: "USD")))
                            .fontWeight(.semibold)
                    }
                } header: {
                    Text("Summary")
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func loadHourlyMetrics() {
        Task {
            let metrics = await viewModel.getHourlyMetrics(hours: 24)
            await MainActor.run {
                hourlyMetrics = metrics
            }
        }
    }

    private func formatHour(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatTokensShort(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    // MARK: - Setup Tab Helpers
    private func refreshStatus() {
        telemetryEnabled = ClaudeConfigService.isTelemetryEnabled()
        otelEndpoint = ClaudeConfigService.getOTelEndpoint()
        prometheusHost = viewModel.prometheusHost
        prometheusPort = String(viewModel.prometheusPort)

        // Check OTel Collector connection
        Task {
            await checkOTelCollectorConnection()
        }
    }

    private func checkOTelCollectorConnection() async {
        // Extract host from gRPC endpoint and use HTTP port for health check
        guard !otelEndpoint.isEmpty,
              let endpointURL = URL(string: otelEndpoint),
              let host = endpointURL.host else {
            await MainActor.run { otelCollectorConnected = false }
            return
        }

        // Use HTTP port for status check
        let httpEndpoint = "http://\(host):\(otelHttpPort)"
        guard let url = URL(string: httpEndpoint) else {
            await MainActor.run { otelCollectorConnected = false }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                // OTel Collector returns 200, 400, 404, or 415 when reachable
                let connected = [200, 400, 404, 415].contains(httpResponse.statusCode)
                await MainActor.run { otelCollectorConnected = connected }
            }
        } catch {
            await MainActor.run { otelCollectorConnected = false }
        }
    }

    private func applyPrometheusSettings() {
        viewModel.prometheusHost = prometheusHost.isEmpty ? "localhost" : prometheusHost
        viewModel.prometheusPort = Int(prometheusPort) ?? 9090
        viewModel.updatePrometheusService()
    }

    private func updateTelemetry(enable: Bool) {
        do {
            if enable {
                let endpoint = otelEndpoint.isEmpty ? nil : otelEndpoint
                try ClaudeConfigService.enableTelemetry(endpoint: endpoint)
                statusMessage = "Telemetry enabled. Restart Claude Code to apply."
            } else {
                try ClaudeConfigService.disableTelemetry()
                statusMessage = "Telemetry disabled. Restart Claude Code to apply."
            }
            telemetryEnabled = enable
        } catch {
            statusMessage = "Failed: \(error.localizedDescription)"
        }
    }

    private func openOTelSettingsWindow() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "OpenTelemetry Settings"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = false

        let hostingView = NSHostingView(rootView: OTelSettingsModal(
            currentEndpoint: otelEndpoint,
            onSave: { newEndpoint in
                do {
                    try ClaudeConfigService.updateEndpoint(newEndpoint)
                    self.otelEndpoint = newEndpoint
                    self.statusMessage = "Endpoint updated. Restart Claude Code to apply."
                } catch {
                    self.statusMessage = "Failed: \(error.localizedDescription)"
                }
                panel.close()
            },
            onCancel: {
                panel.close()
            }
        ))
        panel.contentView = hostingView
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - About Tab
    private var aboutTab: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Claude Usage Widget")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Version 1.0.0")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()
                .frame(width: 200)

            Text("Track your Anthropic API usage directly from the menu bar.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)

            Link("View on GitHub", destination: URL(string: "https://github.com")!)
                .font(.caption)

            Spacer()
        }
        .padding(30)
    }

}

// MARK: - Launch at Login Toggle
struct LaunchAtLoginToggle: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false

    var body: some View {
        Toggle("Launch at Login", isOn: $launchAtLogin)
            .onChange(of: launchAtLogin) { newValue in
                print("Launch at login: \(newValue)")
            }
    }
}

// MARK: - OTel Settings Modal
struct OTelSettingsModal: View {
    let currentEndpoint: String
    let onSave: (String) -> Void
    let onCancel: () -> Void

    @State private var host: String = ""
    @State private var port: String = ""
    @State private var testResult: TestResult = .none
    @State private var isTesting = false

    enum TestResult {
        case none
        case success
        case failure(String)
    }

    init(currentEndpoint: String, onSave: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.currentEndpoint = currentEndpoint
        self.onSave = onSave
        self.onCancel = onCancel

        // Parse current endpoint into host and port
        if let url = URL(string: currentEndpoint) {
            _host = State(initialValue: url.host ?? "localhost")
            _port = State(initialValue: url.port.map { String($0) } ?? "4317")
        } else {
            _host = State(initialValue: "localhost")
            _port = State(initialValue: "4317")
        }
    }

    private var endpoint: String {
        "http://\(host):\(port)"
    }

    var body: some View {
        VStack(spacing: 20) {
            Text("OpenTelemetry Server Settings")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Host")
                        .frame(width: 50, alignment: .leading)
                    TextField("localhost", text: $host)
                        .textFieldStyle(.roundedBorder)
                }

                HStack {
                    Text("Port")
                        .frame(width: 50, alignment: .leading)
                    TextField("4317", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                }

                HStack {
                    Text("Endpoint:")
                        .foregroundColor(.secondary)
                    Text(endpoint)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Test Result
            if case .success = testResult {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Connection successful")
                        .foregroundColor(.green)
                }
            } else if case .failure(let message) = testResult {
                HStack {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                    Text(message)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }

            Divider()

            HStack(spacing: 12) {
                Button("Test") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || host.isEmpty || port.isEmpty)

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.7)
                }

                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)

                Button("Confirm") {
                    onSave(endpoint)
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.isEmpty || port.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
    }

    private func testConnection() {
        isTesting = true
        testResult = .none

        // Test TCP connection to the endpoint
        DispatchQueue.global(qos: .userInitiated).async {
            let result = testTCPConnection(host: host, port: UInt16(port) ?? 4317)
            DispatchQueue.main.async {
                isTesting = false
                testResult = result
            }
        }
    }

    private func testTCPConnection(host: String, port: UInt16) -> TestResult {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)

        guard status == 0, let addrInfo = result else {
            return .failure("Cannot resolve host")
        }
        defer { freeaddrinfo(result) }

        let sock = socket(addrInfo.pointee.ai_family, addrInfo.pointee.ai_socktype, addrInfo.pointee.ai_protocol)
        guard sock >= 0 else {
            return .failure("Cannot create socket")
        }
        defer { close(sock) }

        // Set timeout
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        let connectResult = connect(sock, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
        if connectResult == 0 {
            return .success
        } else {
            return .failure("Connection refused")
        }
    }
}

// MARK: - OTel Settings Modal
struct OTelSettingsView: View {
    @Binding var endpoint: String
    @Binding var httpPort: Int
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tempEndpoint: String = ""
    @State private var tempHttpPort: String = ""
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("OTel Collector Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section {
                    TextField("http://localhost:4317", text: $tempEndpoint)
                        .textFieldStyle(.roundedBorder)
                } header: {
                    Text("gRPC Endpoint (for Claude Code)")
                } footer: {
                    Text("Claude Code sends telemetry to this endpoint")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section {
                    TextField("4318", text: $tempHttpPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                } header: {
                    Text("HTTP Port (for status check)")
                } footer: {
                    Text("Used to verify OTel Collector is running")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if !testResult.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: testResult.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testResult.contains("Success") ? .green : .red)
                            Text(testResult)
                                .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .disabled(isTesting || tempEndpoint.isEmpty)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    httpPort = Int(tempHttpPort) ?? 4318
                    onSave(tempEndpoint)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tempEndpoint.isEmpty)
            }
            .padding()
        }
        .frame(width: 400, height: 320)
        .onAppear {
            tempHttpPort = String(httpPort)
            tempEndpoint = endpoint
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = ""

        // Extract host from gRPC endpoint and use HTTP port for test
        guard let endpointURL = URL(string: tempEndpoint),
              let host = endpointURL.host else {
            testResult = "Failed: Invalid endpoint URL"
            isTesting = false
            return
        }

        let port = Int(tempHttpPort) ?? 4318
        let httpEndpoint = "http://\(host):\(port)"

        guard let url = URL(string: httpEndpoint) else {
            testResult = "Failed: Invalid HTTP URL"
            isTesting = false
            return
        }

        Task {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 5

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    // OTel collector returns 200, 400, 404, or 415 when reachable
                    if [200, 400, 404, 415].contains(httpResponse.statusCode) {
                        await MainActor.run {
                            testResult = "Success: OTel Collector is reachable at \(httpEndpoint)"
                            isTesting = false
                        }
                    } else {
                        await MainActor.run {
                            testResult = "Warning: Status \(httpResponse.statusCode)"
                            isTesting = false
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Prometheus Settings Modal
struct PrometheusSettingsView: View {
    @Binding var host: String
    @Binding var port: String
    var onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var tempHost: String = ""
    @State private var tempPort: String = ""
    @State private var testResult: String = ""
    @State private var isTesting: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Prometheus Settings")
                    .font(.headline)
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section {
                    HStack {
                        Text("Host")
                            .frame(width: 50, alignment: .leading)
                        TextField("localhost", text: $tempHost)
                            .textFieldStyle(.roundedBorder)
                    }

                    HStack {
                        Text("Port")
                            .frame(width: 50, alignment: .leading)
                        TextField("9090", text: $tempPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Spacer()
                    }
                } header: {
                    Text("Connection")
                }

                if !testResult.isEmpty {
                    Section {
                        HStack {
                            Image(systemName: testResult.contains("Success") ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(testResult.contains("Success") ? .green : .red)
                            Text(testResult)
                                .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Footer
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .buttonStyle(.bordered)
                .disabled(isTesting)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)

                Button("Save") {
                    host = tempHost.isEmpty ? "localhost" : tempHost
                    port = tempPort.isEmpty ? "9090" : tempPort
                    onSave()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 350, height: 280)
        .onAppear {
            tempHost = host
            tempPort = port
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = ""

        let testHost = tempHost.isEmpty ? "localhost" : tempHost
        let testPort = Int(tempPort) ?? 9090

        Task {
            let url = URL(string: "http://\(testHost):\(testPort)/api/v1/status/runtimeinfo")!
            var request = URLRequest(url: url)
            request.timeoutInterval = 5

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    await MainActor.run {
                        testResult = "Success: Connected to Prometheus"
                        isTesting = false
                    }
                } else {
                    await MainActor.run {
                        testResult = "Failed: Invalid response"
                        isTesting = false
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "Failed: \(error.localizedDescription)"
                    isTesting = false
                }
            }
        }
    }
}

#Preview {
    SettingsView(viewModel: UsageViewModel())
}
