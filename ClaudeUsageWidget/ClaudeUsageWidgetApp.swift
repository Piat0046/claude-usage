import SwiftUI
import AppKit

@main
struct ClaudeUsageWidgetApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover: NSPopover?
    var viewModel = UsageViewModel()

    func applicationDidFinishLaunching(_ notification: Notification) {

        // Create status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Claude Usage")
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create popover
        popover = NSPopover()
        popover?.contentSize = NSSize(width: 300, height: 400)
        popover?.behavior = .transient

        // Initial update
        updateStatusBar()

        // Update status bar periodically
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateStatusBar()
            }
        }
    }

    private func updateStatusBar() {
        guard let button = statusItem?.button else { return }

        let percent = viewModel.currentSessionUsagePercent
        let hasData = viewModel.currentSessionApiRequestCount > 0 || viewModel.hasMetrics

        if hasData {
            button.title = " \(Int(percent))%"
        } else {
            button.title = ""
        }
    }

    @objc func togglePopover() {
        guard let popover = popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            if let button = statusItem?.button {
                popover.contentViewController = NSHostingController(rootView: MenuBarView(viewModel: viewModel))
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }
}
