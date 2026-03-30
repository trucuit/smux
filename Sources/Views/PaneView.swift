import SwiftUI

// Colors sourced from DesignTokens
private let bgDark = Tokens.bgTerminal
private let bgTitlebar = Tokens.bgTitlebar
private let borderDim = Tokens.borderDim
private let attentionOrange = Tokens.attention
private let activeGreen = Tokens.active
private let focusBlue = Tokens.focus

struct PaneView: View {
    @EnvironmentObject var workspaceManager: WorkspaceManager
    @ObservedObject var panel: TerminalPanel
    @ObservedObject var workspace: Workspace
    let nodeID: UUID

    private var isFocused: Bool {
        workspace.focusedPanelID == panel.id
    }

    private var watchIcon: String {
        switch panel.watchMode {
        case .off: return "bell.slash"
        case .on: return "bell.fill"
        case .silent: return "bell"
        }
    }

    private var watchHelp: String {
        switch panel.watchMode {
        case .off: return "Notifications: off"
        case .on: return "Notifications: on"
        case .silent: return "Notifications: silent"
        }
    }

    private var borderColor: Color {
        if panel.needsAttention {
            return attentionOrange.opacity(0.5)
        }
        if isFocused {
            return focusBlue.opacity(0.5)
        }
        if case .active = panel.activityState {
            return activeGreen.opacity(0.5)
        }
        return borderDim
    }

    private var borderWidth: CGFloat {
        if panel.needsAttention || isFocused { return Tokens.borderFocused }
        return Tokens.borderDefault
    }

    var body: some View {
        VStack(spacing: 0) {
            // Minimal title bar
            HStack(spacing: 6) {
                if panel.isRenaming {
                    RenameField(text: $panel.title) {
                        panel.hasCustomTitle = !panel.title.trimmingCharacters(in: .whitespaces).isEmpty
                        panel.isRenaming = false
                    }
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: 200)
                } else {
                    Text(panel.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(isFocused ? .white.opacity(Tokens.textPrimary) : .white.opacity(Tokens.textSecondary))
                        .lineLimit(1)
                        .contextMenu {
                            Button("Rename") {
                                panel.isRenaming = true
                            }
                        }
                }

                Spacer()

                if case .exited(let code) = panel.activityState {
                    Text("exit \(code)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(code == 0 ? .white.opacity(0.3) : .red.opacity(0.8))
                }

                // Watch toggle + split/close buttons
                HStack(spacing: 0) {
                    PaneTitleButton(
                        systemName: watchIcon,
                        help: watchHelp
                    ) {
                        panel.watchMode = panel.watchMode.next
                    }

                    PaneTitleButton(systemName: "square.split.2x1", help: "Split Right (⌘→)") {
                        workspace.focusedPanelID = panel.id
                        workspace.splitFocusedPane(direction: .horizontal)
                    }
                    PaneTitleButton(systemName: "square.split.1x2", help: "Split Down (⌘↓)") {
                        workspace.focusedPanelID = panel.id
                        workspace.splitFocusedPane(direction: .vertical)
                    }
                    if workspace.rootNode.leafCount > 1 {
                        PaneTitleButton(systemName: "xmark", help: "Close (⌘W)") {
                            workspace.focusedPanelID = panel.id
                            workspace.closeFocusedPane()
                        }
                    }
                }
            }
            .padding(.horizontal, Tokens.titlebarPaddingH)
            .padding(.vertical, Tokens.titlebarPaddingV)
            .background(panel.needsAttention ? attentionOrange.opacity(0.15) : bgTitlebar)
            .onTapGesture {
                panel.clearAttention()
                workspace.focusedPanelID = panel.id
            }

            // Terminal
            TerminalSurfaceView(panel: panel, isFocused: isFocused, isWorkspaceSelected: workspace.id == workspaceManager.selectedWorkspaceID, suppressFocus: workspace.isRenaming)
                .padding(.horizontal, Tokens.terminalPaddingH)
                .onTapGesture {
                    panel.clearAttention()
                    workspace.focusedPanelID = panel.id
                }
        }
        .background(bgDark)
        .clipShape(RoundedRectangle(cornerRadius: Tokens.paneRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Tokens.paneRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: borderWidth)
        )
        .animation(Tokens.stateTransition, value: isFocused)
        .animation(Tokens.stateTransition, value: panel.needsAttention)
    }
}

struct PaneTitleButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.white.opacity(isHovered ? 0.85 : Tokens.textSecondary))
                .frame(width: 24, height: 24)
                .background(isHovered ? Color.white.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in isHovered = hovering }
        .help(help)
        .accessibilityLabel(help)
    }
}

struct RenameField: View {
    @Binding var text: String
    var onCommit: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $text)
            .textFieldStyle(.plain)
            .focused($isFocused)
            .onSubmit { onCommit() }
            .onExitCommand { onCommit() }
            .onAppear { isFocused = true }
            .onChange(of: isFocused) { _, focused in
                if !focused { onCommit() }
            }
    }
}
