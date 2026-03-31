import Foundation
import AppKit
import Combine
import UniformTypeIdentifiers

struct DroppedMediaItem: Identifiable, Equatable {
    enum Kind {
        case image
        case video
    }

    let url: URL
    let kind: Kind

    var id: String {
        url.absoluteString
    }

    init?(url: URL) {
        guard url.isFileURL else { return nil }
        let pathExtension = url.pathExtension.lowercased()
        guard let contentType = UTType(filenameExtension: pathExtension) else { return nil }

        if contentType.conforms(to: .image) {
            kind = .image
        } else if contentType.conforms(to: .movie) {
            kind = .video
        } else {
            return nil
        }

        self.url = url
    }
}

@MainActor
final class TerminalPanel: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var activityState: ActivityState = .idle
    @Published var workingDirectory: String?
    /// Notification level for this terminal.
    @Published var watchMode: WatchMode = .off
    /// Set when a watched terminal finishes work while not focused.
    @Published var needsAttention: Bool = false
    @Published var isRenaming: Bool = false
    @Published var recentDroppedMedia: [DroppedMediaItem] = []
    /// Whether the title was manually set by the user (prevents shell title overrides).
    var hasCustomTitle: Bool = false

    var lastOutputTime: Date = Date()
    /// Set when user presses Enter — only then do we start measuring activity.
    var commandSubmitted: Bool = false
    /// When the monitored activity burst started (nil if not tracking).
    var activeSinceTime: Date? = nil
    /// Set by ActivityDetector tick — whether the user is currently looking at this terminal.
    var isCurrentlyVisible: Bool = false
    /// Whether stdout arrived while the user wasn't looking at this terminal.
    var outputSinceDefocus: Bool = false
    var command: String?
    /// Scrollback text to replay into the terminal on first creation (from session restore).
    var scrollbackToRestore: String?
    /// Whether the user has run any command since this terminal was created/restored.
    var hasHadActivity: Bool = false

    /// The actual terminal NSView — kept here so it survives SwiftUI view lifecycle.
    var terminalView: NSView?

    init(id: UUID = UUID(), title: String = "Terminal", command: String? = nil, workingDirectory: String? = nil) {
        self.id = id
        self.title = title
        self.command = command
        self.workingDirectory = workingDirectory
    }

    /// Called when user presses Enter in the terminal.
    func recordCommandSubmitted() {
        commandSubmitted = true
        hasHadActivity = true
    }

    /// Called on every chunk of output from the PTY.
    func recordOutput() {
        lastOutputTime = Date()
        // Any new output clears attention
        if needsAttention {
            needsAttention = false
        }
        // Track if output happened while user wasn't looking
        if !isCurrentlyVisible {
            outputSinceDefocus = true
        }
        // Only start activity tracking if user submitted a command
        if commandSubmitted && activityState != .active {
            activityState = .active
            activeSinceTime = Date()
        }
    }

    func recordExit(code: Int32) {
        activityState = .exited(code: code)
        activeSinceTime = nil
        commandSubmitted = false
    }

    /// Called by ActivityDetector when output stops.
    func transitionToIdle() {
        activityState = .idle
        activeSinceTime = nil
        commandSubmitted = false
        outputSinceDefocus = false
    }

    func clearAttention() {
        if needsAttention {
            needsAttention = false
        }
    }

    func recordTitleChange(_ newTitle: String) {
        if !newTitle.isEmpty && !hasCustomTitle {
            title = newTitle
        }
    }

    func recordDirectoryChange(_ directory: String?) {
        workingDirectory = directory
    }

    func recordDroppedMedia(urls: [URL], maxItems: Int = 8) {
        let newItems = urls.compactMap(DroppedMediaItem.init(url:))
        guard !newItems.isEmpty else { return }

        var seenPaths = Set<String>()
        let merged = (newItems + recentDroppedMedia).filter { item in
            seenPaths.insert(item.url.path).inserted
        }

        recentDroppedMedia = Array(merged.prefix(maxItems))
    }

    func removeDroppedMedia(_ item: DroppedMediaItem) {
        recentDroppedMedia.removeAll { $0 == item }
    }

    func clearDroppedMedia() {
        recentDroppedMedia.removeAll()
    }
}
