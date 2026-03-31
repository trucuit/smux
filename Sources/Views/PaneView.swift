import SwiftUI
import AppKit
import AVKit

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
    @State private var selectedMedia: DroppedMediaItem?

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

    private func insertMediaPath(_ item: DroppedMediaItem) {
        (panel.terminalView as? SmuxTerminalView)?.insertMediaPath(item.url)
    }

    private func copyMediaPath(_ item: DroppedMediaItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(item.url.path, forType: .string)
    }

    var body: some View {
        ZStack {
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

                ZStack(alignment: .bottomTrailing) {
                    // Terminal
                    TerminalSurfaceView(panel: panel, isFocused: isFocused, isWorkspaceSelected: workspace.id == workspaceManager.selectedWorkspaceID, suppressFocus: workspace.isRenaming)
                        .padding(.horizontal, Tokens.terminalPaddingH)
                        .onTapGesture {
                            panel.clearAttention()
                            workspace.focusedPanelID = panel.id
                        }

                    if !panel.recentDroppedMedia.isEmpty {
                        DroppedMediaStrip(
                            items: panel.recentDroppedMedia,
                            onSelect: { item in
                                selectedMedia = item
                            },
                            onRemove: { item in
                                panel.removeDroppedMedia(item)
                                if selectedMedia == item {
                                    selectedMedia = nil
                                }
                            },
                            onClearAll: {
                                panel.clearDroppedMedia()
                                selectedMedia = nil
                            }
                        )
                        .padding(.trailing, Tokens.terminalPaddingH + 4)
                        .padding(.bottom, 10)
                    }
                }
            }
            if let selectedMedia {
                DroppedMediaLightbox(
                    item: selectedMedia,
                    onClose: {
                        self.selectedMedia = nil
                    },
                    onRemove: {
                        panel.removeDroppedMedia(selectedMedia)
                        self.selectedMedia = nil
                    },
                    onInsertPath: {
                        insertMediaPath(selectedMedia)
                        self.selectedMedia = nil
                    },
                    onCopyPath: {
                        copyMediaPath(selectedMedia)
                    }
                )
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

private struct DroppedMediaStrip: View {
    let items: [DroppedMediaItem]
    let onSelect: (DroppedMediaItem) -> Void
    let onRemove: (DroppedMediaItem) -> Void
    let onClearAll: () -> Void

    private let maxVisibleItems = 4

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(items.prefix(maxVisibleItems))) { item in
                DroppedMediaThumbnail(
                    item: item,
                    onSelect: {
                        onSelect(item)
                    },
                    onRemove: {
                        onRemove(item)
                    }
                )
                .help(item.url.lastPathComponent)
            }

            if items.count > maxVisibleItems {
                Text("+\(items.count - maxVisibleItems)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(Tokens.textPrimary))
                    .padding(.horizontal, 10)
                    .frame(height: 68)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if items.count > 1 {
                MediaQuickActionButton(systemName: "trash", help: "Clear media previews", action: onClearAll)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct DroppedMediaThumbnail: View {
    let item: DroppedMediaItem
    let onSelect: () -> Void
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSelect) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                        .frame(width: 68, height: 68)

                    previewContent
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text(item.kind == .image ? "IMG" : "VID")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white.opacity(Tokens.textPrimary))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
            .buttonStyle(.plain)

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(Tokens.textPrimary))
                    .shadow(color: .black.opacity(0.4), radius: 2)
            }
            .buttonStyle(.plain)
            .padding(4)
            .help("Remove preview")
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch item.kind {
        case .image:
            if let image = NSImage(contentsOf: item.url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder(systemName: "photo")
            }
        case .video:
            placeholder(systemName: "film")
        }
    }

    private func placeholder(systemName: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
            Image(systemName: systemName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.white.opacity(Tokens.textPrimary))
        }
    }
}

private struct MediaQuickActionButton: View {
    let systemName: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(Tokens.textPrimary))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

private struct DroppedMediaLightbox: View {
    let item: DroppedMediaItem
    let onClose: () -> Void
    let onRemove: () -> Void
    let onInsertPath: () -> Void
    let onCopyPath: () -> Void
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture {
                    onClose()
                }

            VStack(spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.url.lastPathComponent)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white.opacity(Tokens.textPrimary))
                        Text(item.url.path)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(Tokens.textSecondary))
                            .textSelection(.enabled)
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        MediaQuickActionButton(systemName: "arrow.down.doc", help: "Insert path into terminal", action: onInsertPath)
                        MediaQuickActionButton(systemName: "doc.on.doc", help: "Copy path", action: onCopyPath)
                        MediaQuickActionButton(systemName: "folder", help: "Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.url])
                        }
                        MediaQuickActionButton(systemName: "arrow.up.forward.app", help: "Open file") {
                            NSWorkspace.shared.open(item.url)
                        }
                        MediaQuickActionButton(systemName: "trash", help: "Remove preview", action: onRemove)
                        MediaQuickActionButton(systemName: "xmark", help: "Close preview", action: onClose)
                    }
                }

                Group {
                    switch item.kind {
                    case .image:
                        if let image = NSImage(contentsOf: item.url) {
                            ScrollView([.horizontal, .vertical]) {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            unavailableMessage("Could not load image preview.")
                        }
                    case .video:
                        if let player {
                            VideoPlayer(player: player)
                        } else {
                            unavailableMessage("Could not load video preview.")
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.18))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(20)
            .frame(maxWidth: 920, maxHeight: 720)
            .background(Color.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard item.kind == .video else { return }
            player = AVPlayer(url: item.url)
        }
        .onDisappear {
            player?.pause()
        }
    }

    private func unavailableMessage(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: item.kind == .image ? "photo" : "film")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
