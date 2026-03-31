import Foundation
import AppKit
import UserNotifications

@MainActor
final class ActivityDetector: ObservableObject {
    /// How long a terminal must be silent before going idle.
    var idleThreshold: TimeInterval = 3.0
    private var timer: Timer?
    private var keyMonitor: Any?
    private weak var workspaceManager: WorkspaceManager?
    private let attentionSound = NSSound(named: "Tink")

    func start(workspaceManager: WorkspaceManager) {
        self.workspaceManager = workspaceManager
        requestNotificationPermission()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak workspaceManager, weak self] _ in
            guard let manager = workspaceManager, let self = self else { return }
            Task { @MainActor in
                self.tick(manager: manager)
            }
        }

        // Single global key monitor for Enter detection
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                // Return (36) or numpad Enter (76) — only when a terminal view has focus.
                if event.keyCode == 36 || event.keyCode == 76,
                   let terminalView = event.window?.firstResponder as? SmuxTerminalView {
                    if terminalView.insertMultilineBreakIfNeeded(for: event) {
                        return nil
                    }

                    Task { @MainActor [weak self] in
                        self?.handleEnterPress()
                    }
                }
                return event
            }
        }
    }

    private func handleEnterPress() {
        guard let manager = workspaceManager,
              let workspace = manager.selectedWorkspace,
              let focusedID = workspace.focusedPanelID,
              let panel = workspace.panels[focusedID] else { return }
        panel.recordCommandSubmitted()
    }

    private func tick(manager: WorkspaceManager) {
        let now = Date()
        for workspace in manager.workspaces {
            for panel in workspace.panels.values {
                // The user is "actually looking" at the terminal only when ALL three hold:
                // 1. smux is the foreground app
                // 2. This workspace is the selected one
                // 3. This terminal is the focused pane
                let isActuallyVisible = NSApp.isActive
                    && workspace.id == manager.selectedWorkspaceID
                    && panel.id == workspace.focusedPanelID

                panel.isCurrentlyVisible = isActuallyVisible
                // Reset the flag when user looks at the terminal
                if isActuallyVisible {
                    panel.outputSinceDefocus = false
                }

                guard case .active = panel.activityState else { continue }
                guard now.timeIntervalSince(panel.lastOutputTime) > idleThreshold else { continue }

                let wasCommand = panel.commandSubmitted
                let hadOutput = panel.outputSinceDefocus
                panel.transitionToIdle()

                if wasCommand && !isActuallyVisible && hadOutput && panel.watchMode != .off {
                    panel.needsAttention = true
                    workspace.objectWillChange.send()
                    if panel.watchMode == .on {
                        attentionSound?.play()
                    }
                    if !NSApp.isActive {
                        sendNotification(title: panel.title)
                    }
                }
            }
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func sendNotification(title: String) {
        let content = UNMutableNotificationContent()
        content.title = "Terminal done"
        content.body = "\(title) has finished running"

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
}
