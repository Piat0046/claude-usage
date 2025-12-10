import SwiftUI

// MARK: - Settings Button Helper
struct SettingsButton<Label: View>: View {
    let label: () -> Label

    init(@ViewBuilder label: @escaping () -> Label) {
        self.label = label
    }

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink(label: label)
        } else {
            Button(action: openSettings, label: label)
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}

struct MenuBarView: View {
    @ObservedObject var viewModel: UsageViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Claude Usage")
                    .font(.headline)
                Spacer()
                SettingsButton {
                    Image(systemName: "gear")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)

            if viewModel.isLoading && viewModel.lastUpdated == nil {
                loadingView
            } else if let error = viewModel.error {
                errorView(error)
            } else if !viewModel.hasMetrics {
                noDataView
            } else {
                usageContent
            }

            Divider()

            // Footer
            footerView
        }
        .padding()
        .frame(width: 280)
    }

    // MARK: - Subviews
    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No Data Yet")
                .font(.headline)
            Text("Enable telemetry in Settings > Setup and restart Claude Code.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            SettingsButton {
                Text("Open Settings")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Loading...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error, forType: .string)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button("Retry") {
                    Task {
                        await viewModel.refresh()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var usageContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Token Usage
            VStack(alignment: .leading, spacing: 6) {
                Text("Usage")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Tokens")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(formatTokens(viewModel.claudeCodeTotalTokens.input + viewModel.claudeCodeTotalTokens.output))
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Cost")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(viewModel.claudeCodeTotalCost.formatted(.currency(code: "USD")))
                            .font(.callout)
                            .fontWeight(.semibold)
                    }
                }
                .padding(10)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }

            Divider()

            // Session Stats
            VStack(alignment: .leading, spacing: 6) {
                Text("Session Stats")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Sessions")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.sessionCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Time")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(viewModel.activeTimeFormatted)
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Commits")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(viewModel.commitCount)")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(8)
            }

        }
    }

    private var footerView: some View {
        HStack {
            if viewModel.isLoading {
                ProgressView()
                    .scaleEffect(0.5)
                    .frame(width: 16, height: 16)
            }
            Text("Updated \(viewModel.timeSinceLastUpdate)")
                .font(.caption2)
                .foregroundColor(.secondary)

            Spacer()

            Button("Refresh") {
                Task {
                    await viewModel.refresh()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .disabled(viewModel.isLoading)

            SettingsButton {
                Text("Settings")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
    }

    private func formatTokens(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

#Preview {
    MenuBarView(viewModel: UsageViewModel())
}
