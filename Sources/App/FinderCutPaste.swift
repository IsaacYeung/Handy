import AppKit

final class FinderCutPaste {
    static let shared = FinderCutPaste()
    private init() {}

    private(set) var pendingURLs: [URL] = []
    private(set) var cutInProgress = false
    // True when a cut has been initiated (either in-flight or complete)
    var hasPending: Bool { !pendingURLs.isEmpty || cutInProgress }

    // MARK: - Cut

    // Dispatches AppleScript to a background thread so the main run loop
    // stays free — required for macOS to show the Automation permission
    // dialog the first time Handy tries to control Finder.
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
            guard let target = self.finderWindowTarget() else { return }
            let destDir = URL(fileURLWithPath: target)
            // Skip files already in the destination — prevents accidental
            // "(2)" duplicates when the user pastes into the same folder.
            let sources = urlsToMove.filter {
                $0.deletingLastPathComponent().path != destDir.path
            }
            guard !sources.isEmpty else { return }
            var errors: [String] = []
            for src in sources {
                let dst = Self.uniqueDestination(src, in: destDir)
                do {
                    try FileManager.default.moveItem(at: src, to: dst)
                } catch {
                    errors.append("\(src.lastPathComponent): \(error.localizedDescription)")
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

    private static func uniqueDestination(_ src: URL, in dir: URL) -> URL {
        var dest = dir.appendingPathComponent(src.lastPathComponent)
        guard FileManager.default.fileExists(atPath: dest.path) else { return dest }
        let name = src.deletingPathExtension().lastPathComponent
        let ext  = src.pathExtension
        var n = 2
        repeat {
            let candidate = ext.isEmpty ? "\(name) (\(n))" : "\(name) (\(n)).\(ext)"
            dest = dir.appendingPathComponent(candidate)
            n += 1
        } while FileManager.default.fileExists(atPath: dest.path)
        return dest
    }

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
        var err: NSDictionary?
        guard let desc = NSAppleScript(source: src)?.executeAndReturnError(&err),
              desc.numberOfItems > 0 else { return [] }
        return (1...desc.numberOfItems).compactMap { desc.atIndex($0)?.stringValue }
    }

    private func finderWindowTarget() -> String? {
        let src = """
        tell application "Finder"
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        var err: NSDictionary?
        return NSAppleScript(source: src)?.executeAndReturnError(&err).stringValue
    }

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
