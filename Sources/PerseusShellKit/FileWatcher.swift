import Foundation

/// Watches one file on disk and reports when its contents may have changed,
/// so an open .json file can be re-rendered as the user edits it.
///
/// It uses a vnode DispatchSource on an open file descriptor. That catches
/// in-place writes directly, but most editors save atomically: they write a
/// temporary file and rename it over the original, which deletes the inode we
/// are watching. On a `.delete` or `.rename` event the watcher therefore closes
/// the stale descriptor and reopens the path, retrying briefly in case the
/// editor has not finished the rename yet. Bursts of events (a write followed
/// by an attribute change, or several partial writes) are coalesced into one
/// `.changed` callback by a short debounce.
///
/// The source's handlers retain the watcher, so it stays alive until `stop()`
/// is called; the owner must call it when it is done.
@MainActor
final class FileWatcher {
    enum Event {
        /// The file was written to (or replaced). The owner should re-read it.
        case changed
        /// The file was deleted or moved and did not reappear.
        case disappeared
    }

    let url: URL

    private let onEvent: (Event) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pendingNotify: DispatchWorkItem?
    /// Set when the inode we watch has been deleted or renamed, so the next
    /// notification must reopen the path first.
    private var needsReopen = false

    /// How long to wait after the last event before notifying, so an editor's
    /// multi-step save produces a single reload.
    private static let debounce: TimeInterval = 0.15
    /// How many times, and how often, to look for the file again after an
    /// atomic save removed the one we were watching.
    private static let reopenAttempts = 10
    private static let reopenInterval: TimeInterval = 0.1

    /// Returns nil if the file cannot be opened for watching.
    init?(url: URL, onEvent: @escaping @MainActor (Event) -> Void) {
        self.url = url
        self.onEvent = onEvent
        guard arm() else { return nil }
    }

    /// Stops watching. Safe to call more than once.
    func stop() {
        pendingNotify?.cancel()
        pendingNotify = nil
        source?.cancel()
        source = nil
    }

    // MARK: Internals

    /// Opens the file and installs a vnode source on it. Returns false if the
    /// file could not be opened, leaving the watcher unarmed.
    private func arm() -> Bool {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return false }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .attrib, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [self] in
            MainActor.assumeIsolated {
                handle(flags: source.data)
            }
        }
        // The descriptor belongs to the source; closing it anywhere else would
        // race with the kernel still delivering events.
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        self.source = source
        needsReopen = false
        return true
    }

    private func handle(flags: DispatchSource.FileSystemEvent) {
        if !flags.isDisjoint(with: [.delete, .rename, .revoke]) {
            // The inode is gone (atomic save, or a real delete). Drop the
            // source now; `notify` reopens the path once things settle.
            needsReopen = true
            source?.cancel()
            source = nil
        }
        scheduleNotify(attemptsLeft: Self.reopenAttempts)
    }

    private func scheduleNotify(after delay: TimeInterval = FileWatcher.debounce, attemptsLeft: Int) {
        pendingNotify?.cancel()
        let work = DispatchWorkItem { [self] in
            MainActor.assumeIsolated {
                notify(attemptsLeft: attemptsLeft)
            }
        }
        pendingNotify = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func notify(attemptsLeft: Int) {
        pendingNotify = nil
        if needsReopen {
            if arm() {
                onEvent(.changed)
            } else if attemptsLeft > 0 {
                // The editor may still be between "remove old" and "rename
                // new into place". Look again shortly.
                scheduleNotify(after: Self.reopenInterval, attemptsLeft: attemptsLeft - 1)
            } else {
                onEvent(.disappeared)
            }
        } else {
            onEvent(.changed)
        }
    }
}
