import SwiftUI
import SwiftTerm
import Darwin
import AppKit

struct TerminalSurfaceView: NSViewRepresentable {
    let panel: TerminalPanel
    let isFocused: Bool
    let isWorkspaceSelected: Bool
    var suppressFocus: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator(panel: panel)
    }

    func makeNSView(context: Context) -> NSView {
        // Reuse existing terminal view if the panel already has one (survives workspace switches)
        if let existing = panel.terminalView as? SmuxTerminalView {
            context.coordinator.terminalView = existing
            return existing
        }

        let tv = SmuxTerminalView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        tv.panel = panel
        tv.processDelegate = context.coordinator
        context.coordinator.terminalView = tv

        // Theme from design tokens
        tv.font = Tokens.terminalFont
        tv.nativeBackgroundColor = Tokens.termBackground
        tv.nativeForegroundColor = Tokens.termForeground

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let home = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        let cwd = panel.workingDirectory ?? home

        var env = Terminal.getEnvironmentVariables(termName: "xterm-256color")
        env.append("LANG=en_US.UTF-8")

        tv.startProcess(executable: shell, args: [], environment: env, execName: nil, currentDirectory: cwd)

        // Replay saved scrollback from previous session
        if let scrollback = panel.scrollbackToRestore {
            panel.scrollbackToRestore = nil
            // Convert newlines to CR+LF for terminal emulator and add a separator
            let lines = scrollback.components(separatedBy: "\n")
            let crlfText = lines.joined(separator: "\r\n")
            tv.feed(text: crlfText + "\r\n")
        }

        // Store on panel so it survives SwiftUI lifecycle
        panel.terminalView = tv

        return tv
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if isFocused && isWorkspaceSelected && !panel.isRenaming && !suppressFocus {
            DispatchQueue.main.async {
                if let window = nsView.window, window.firstResponder !== nsView {
                    window.makeFirstResponder(nsView)
                }
            }
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        let panel: TerminalPanel
        weak var terminalView: SmuxTerminalView?

        init(panel: TerminalPanel) {
            self.panel = panel
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
            Task { @MainActor in
                self.panel.recordTitleChange(title)
            }
        }

        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
            Task { @MainActor in
                self.panel.recordDirectoryChange(directory)
            }
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            Task { @MainActor in
                self.panel.recordExit(code: exitCode ?? -1)
            }
        }
    }
}

// MARK: - Process CWD helper

/// Read the current working directory of a process using proc_pidinfo.
func getProcessCWD(pid: pid_t) -> String? {
    var pathInfo = proc_vnodepathinfo()
    let size = MemoryLayout<proc_vnodepathinfo>.size
    let result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &pathInfo, Int32(size))
    guard result == size else { return nil }
    return withUnsafePointer(to: pathInfo.pvi_cdir.vip_path) { ptr in
        ptr.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { cPath in
            String(cString: cPath)
        }
    }
}

// MARK: - Custom Terminal View

final class SmuxTerminalView: LocalProcessTerminalView {
    weak var panel: TerminalPanel?
    private var hasConfiguredDropHandling = false
    private static let multilineRelevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureDropHandlingIfNeeded()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureDropHandlingIfNeeded()
    }

    /// Extract scrollback text from the terminal buffer (for session persistence).
    func getScrollbackText(maxChars: Int = 400_000) -> String? {
        let terminal = getTerminal()

        // getText clamps out-of-range rows, so use a large end row to get everything.
        let start = Position(col: 0, row: 0)
        let end = Position(col: terminal.cols, row: 1_000_000)
        var text = terminal.getText(start: start, end: end)

        // Trim trailing whitespace/newlines
        while text.hasSuffix("\n") || text.hasSuffix(" ") {
            text = String(text.dropLast())
        }

        guard !text.isEmpty else { return nil }

        // Truncate from the front if too long, keeping whole lines
        if text.count > maxChars {
            text = String(text.suffix(maxChars))
            if let firstNewline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: firstNewline)...])
            }
        }

        return text
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureOverlayScroller()
        configureDropHandlingIfNeeded()
    }

    /// Hide the scroller — terminal scrollback is handled via trackpad/keyboard.
    private func configureOverlayScroller() {
        for subview in subviews {
            if let scroller = subview as? NSScroller {
                scroller.isHidden = true
                break
            }
        }
    }

    private func configureDropHandlingIfNeeded() {
        guard !hasConfiguredDropHandling else { return }
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
        hasConfiguredDropHandling = true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        canHandleDrop(sender.draggingPasteboard) ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        canHandleDrop(sender.draggingPasteboard) ? .copy : []
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        canHandleDrop(sender.draggingPasteboard)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let droppedText = droppedInput(from: sender.draggingPasteboard) else {
            return false
        }

        window?.makeFirstResponder(self)
        sendDroppedText(droppedText)
        return true
    }

    private func canHandleDrop(_ pasteboard: NSPasteboard) -> Bool {
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            return true
        }

        if NSImage(pasteboard: pasteboard) != nil {
            return true
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            return true
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return true
        }

        return false
    }

    private func droppedInput(from pasteboard: NSPasteboard) -> String? {
        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            return fileURLs.map { shellEscapePath($0.path) }.joined(separator: " ")
        }

        if let image = NSImage(pasteboard: pasteboard),
           let temporaryURL = writeDroppedImageToTemporaryFile(image) {
            return shellEscapePath(temporaryURL.path)
        }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           !urls.isEmpty {
            return urls.map { shellEscapePath($0.absoluteString) }.joined(separator: " ")
        }

        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return text
        }

        return nil
    }

    private func writeDroppedImageToTemporaryFile(_ image: NSImage) -> URL? {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("smux-dropped-images", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent("dropped-image-\(UUID().uuidString).png")
            try pngData.write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private func shellEscapePath(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }

    func insertMultilineBreakIfNeeded(for event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(Self.multilineRelevantModifiers)
        let isReturnKey = event.keyCode == 36 || event.keyCode == 76
        guard isReturnKey && modifiers == [.command] else {
            return false
        }

        let lineFeed: [UInt8] = [0x0a]
        send(data: lineFeed[...])
        return true
    }

    private func sendDroppedText(_ text: String) {
        if getTerminal().bracketedPasteMode {
            send(data: EscapeSequences.bracketedPasteStart[...])
            send(txt: text)
            send(data: EscapeSequences.bracketedPasteEnd[...])
            return
        }

        send(txt: text)
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        Task { @MainActor [weak self] in
            self?.panel?.recordOutput()
        }
    }

    override func bell(source: Terminal) {
        super.bell(source: source)
    }
}
