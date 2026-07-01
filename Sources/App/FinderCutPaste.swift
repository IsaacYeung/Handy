import AppKit

final class FinderCutPaste {
    static let shared = FinderCutPaste()
    private init() {}

    private(set) var pendingURLs: [URL] = []
    private(set) var cutInProgress = false
    // True when a cut has been initiated (either in-flight or complete)
    var hasPending: Bool { !pendingURLs.isEmpty || cutInProgress }

    // Last completed move, for Cmd+Z undo: (where it was, where it is now)
    private(set) var lastMove: [(from: URL, to: URL)] = []
    var canUndo: Bool { !lastMove.isEmpty }

    // MARK: - Cut

    // AppleScript runs off the main thread (serialized by AppleScriptRunner)
    // so the event-tap callback returns immediately.
    func cut() {
        cutInProgress = true
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }
            let paths = self.selectedFinderPaths()
            DispatchQueue.main.async {
                self.cutInProgress = false
                guard !paths.isEmpty else { return }
                self.pendingURLs = paths.map { URL(fileURLWithPath: $0) }
                self.updateMenuBarBadge()
            }
        }
    }

    // MARK: - Paste (move)

    func paste() {
        // If cut() is still running its AppleScript (fast Cmd+X then Cmd+V),
        // wait up to 2 s for it to populate pendingURLs.
        if cutInProgress {
            DispatchQueue.global(qos: .userInteractive).async { [weak self] in
                guard let self else { return }
                var waited = 0.0
                while self.cutInProgress && waited < 2.0 {
                    Thread.sleep(forTimeInterval: 0.05)
                    waited += 0.05
                }
                DispatchQueue.main.async { self.paste() }
            }
            return
        }
        guard !pendingURLs.isEmpty else { return }
        let urlsToMove = pendingURLs
        pendingURLs = []          // clear badge immediately on key press
        updateMenuBarBadge()

        DispatchQueue.global(qos: .userInteractive).async {
            guard let target = self.finderWindowTarget() else {
                // Destination couldn't be resolved (no Finder window, script
                // failure). Restore the cut instead of dropping it silently.
                DispatchQueue.main.async {
                    self.pendingURLs = urlsToMove
                    self.updateMenuBarBadge()
                }
                return
            }
            let destDir = URL(fileURLWithPath: target)
            // Skip files already in the destination — prevents accidental
            // "(2)" duplicates when the user pastes into the same folder.
            let sources = urlsToMove.filter {
                $0.deletingLastPathComponent().path != destDir.path
            }
            guard !sources.isEmpty else { return }
            var errors: [String] = []
            var moved: [(from: URL, to: URL)] = []
            for src in sources {
                let dst = FileNaming.uniqueDestination(src, in: destDir)
                do {
                    try FileManager.default.moveItem(at: src, to: dst)
                    moved.append((from: src, to: dst))
                } catch {
                    errors.append("\(src.lastPathComponent): \(error.localizedDescription)")
                }
            }
            // Replace (not append) the undo record — Cmd+Z undoes the last move
            DispatchQueue.main.async { self.lastMove = moved }
            if !errors.isEmpty {
                DispatchQueue.main.async { Self.showErrors(errors) }
            }
        }
    }

    // MARK: - Undo (move files back)

    func undo() {
        guard canUndo else { return }
        let record = lastMove
        lastMove = []   // single-shot: the next Cmd+Z goes to Finder's own undo
        DispatchQueue.global(qos: .userInteractive).async {
            var errors: [String] = []
            for move in record.reversed() {
                let originalDir = move.from.deletingLastPathComponent()
                // Restore under the original name, uniquified in case
                // something else took that name in the meantime.
                let dst = FileNaming.uniqueDestination(move.from, in: originalDir)
                do {
                    try FileManager.default.moveItem(at: move.to, to: dst)
                } catch {
                    errors.append("\(move.to.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if !errors.isEmpty {
                DispatchQueue.main.async { Self.showErrors(errors) }
            }
        }
    }

    // MARK: - Cancel

    func cancel() {
        guard hasPending else { return }
        cutInProgress = false
        pendingURLs = []
        updateMenuBarBadge()
    }

    // MARK: - Private helpers

    private func selectedFinderPaths() -> [String] {
        let src = """
        tell application "Finder"
            set sel to selection as alias list
            set out to {}
            repeat with f in sel
                set end of out to POSIX path of f
            end repeat
            return out
        end tell
        """
        guard let desc = AppleScriptRunner.shared.run(src).descriptor,
              desc.numberOfItems > 0 else { return [] }
        return (1...desc.numberOfItems).compactMap { desc.atIndex($0)?.stringValue }
    }

    private func finderWindowTarget() -> String? {
        let src = """
        tell application "Finder"
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        return AppleScriptRunner.shared.run(src).descriptor?.stringValue
    }

    // Reflect cut count in the menu bar icon badge via the AppDelegate
    private func updateMenuBarBadge() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .cutPasteStateChanged, object: self.pendingURLs.count)
        }
    }

    private static func showErrors(_ messages: [String]) {
        let alert = NSAlert()
        alert.messageText = "Some files could not be moved"
        alert.informativeText = messages.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.runModal()
    }
}

extension Notification.Name {
    static let cutPasteStateChanged = Notification.Name("cutPasteStateChanged")
}
