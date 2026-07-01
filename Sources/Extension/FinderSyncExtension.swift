import Cocoa
import FinderSync
import Compression

@objc(FinderSyncExtension)
class FinderSyncExtension: FIFinderSync {

    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    // MARK: - Menu

    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        switch menuKind {
        case .contextualMenuForItems:
            return itemMenu()
        case .contextualMenuForContainer:
            return containerMenu()
        default:
            return nil
        }
    }

    private func itemMenu() -> NSMenu {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        let menu = NSMenu()

        // Extract All Here — only when .zip files are selected
        if selected.contains(where: { $0.pathExtension.lowercased() == "zip" }) {
            menu.addItem(NSMenuItem(title: "Extract All Here",
                                    action: #selector(extractHere),
                                    keyEquivalent: ""))
            menu.addItem(.separator())
        }

        // Copy Path
        let pathTitle = selected.count == 1 ? "Copy Path" : "Copy \(selected.count) Paths"
        menu.addItem(NSMenuItem(title: pathTitle,
                                action: #selector(copyPath),
                                keyEquivalent: ""))

        // Open in Terminal
        menu.addItem(NSMenuItem(title: "Open in Terminal",
                                action: #selector(openInTerminal),
                                keyEquivalent: ""))

        return menu
    }

    private func containerMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "New .txt File Here",
                                action: #selector(newFileHere),
                                keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Open in Terminal",
                                action: #selector(openInTerminal),
                                keyEquivalent: ""))
        return menu
    }

    // MARK: - Actions

    @IBAction func copyPath(_ sender: AnyObject?) {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        guard !selected.isEmpty else { return }
        let paths = selected.map(\.path).joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }

    @IBAction func openInTerminal(_ sender: AnyObject?) {
        let controller = FIFinderSyncController.default()
        let selected = controller.selectedItemURLs() ?? []

        // Prefer the selected directory if exactly one folder is selected;
        // otherwise open the folder being browsed.
        let folderURL: URL
        if selected.count == 1, let first = selected.first {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: first.path, isDirectory: &isDir),
               isDir.boolValue {
                folderURL = first
            } else {
                folderURL = first.deletingLastPathComponent()
            }
        } else {
            folderURL = controller.targetedURL() ?? URL(fileURLWithPath: NSHomeDirectory())
        }

        // Prefer iTerm2 if installed, otherwise fall back to Terminal
        let iterm    = "/Applications/iTerm.app"
        let terminal = "/System/Applications/Utilities/Terminal.app"
        let appPath  = FileManager.default.fileExists(atPath: iterm) ? iterm : terminal

        let t = Process()
        t.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        t.arguments = ["-a", appPath, folderURL.path]
        try? t.run()
    }

    @IBAction func newFileHere(_ sender: AnyObject?) {
        guard let target = FIFinderSyncController.default().targetedURL() else { return }
        let fm = FileManager.default
        var candidate = target.appendingPathComponent("untitled.txt")
        var n = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = target.appendingPathComponent("untitled \(n).txt")
            n += 1
        }
        fm.createFile(atPath: candidate.path, contents: Data(), attributes: nil)
    }

    @IBAction func extractHere(_ sender: AnyObject?) {
        let selected = FIFinderSyncController.default().selectedItemURLs() ?? []
        for url in selected {
            guard url.pathExtension.lowercased() == "zip" else { continue }
            let dir = url.deletingLastPathComponent()

            let accessing    = url.startAccessingSecurityScopedResource()
            let dirAccessing = dir.startAccessingSecurityScopedResource()
            defer {
                if accessing    { url.stopAccessingSecurityScopedResource() }
                if dirAccessing { dir.stopAccessingSecurityScopedResource() }
            }

            let task = Process()
            // ditto -xk is Apple's native ZIP extractor; unlike unzip it never
            // produces __MACOSX folders or ._resource-fork files.
            task.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            task.arguments = ["-xk", url.path, dir.path]
            if (try? task.run()) != nil {
                task.waitUntilExit()
            } else {
                extractSwift(zipURL: url, destDir: dir)
            }
        }
    }

    // MARK: - Swift ZIP fallback

    private func extractSwift(zipURL: URL, destDir: URL) {
        guard let data = try? Data(contentsOf: zipURL) else { return }
        let bytes = [UInt8](data)
        var i = 0

        while i + 30 < bytes.count {
            guard bytes[i] == 0x50, bytes[i+1] == 0x4B,
                  bytes[i+2] == 0x03, bytes[i+3] == 0x04 else { i += 1; continue }

            let method    = Int(bytes[i+8])  | Int(bytes[i+9])  << 8
            let cSize     = Int(bytes[i+18]) | Int(bytes[i+19]) << 8 |
                            Int(bytes[i+20]) << 16 | Int(bytes[i+21]) << 24
            let uSize     = Int(bytes[i+22]) | Int(bytes[i+23]) << 8 |
                            Int(bytes[i+24]) << 16 | Int(bytes[i+25]) << 24
            let fnLen     = Int(bytes[i+26]) | Int(bytes[i+27]) << 8
            let exLen     = Int(bytes[i+28]) | Int(bytes[i+29]) << 8
            let fnStart   = i + 30
            let fnEnd     = fnStart + fnLen
            let dataStart = fnEnd + exLen
            let dataEnd   = dataStart + cSize

            guard fnEnd <= bytes.count, dataEnd <= bytes.count else { break }

            let name = String(bytes: bytes[fnStart..<fnEnd], encoding: .utf8) ?? ""
            let base = (name as NSString).lastPathComponent
            if name.hasPrefix("__MACOSX/") || base == ".DS_Store" || base.hasPrefix("._") {
                i = dataEnd; continue
            }

            let entryURL = destDir.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try? FileManager.default.createDirectory(at: entryURL,
                                                         withIntermediateDirectories: true)
            } else {
                try? FileManager.default.createDirectory(at: entryURL.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                let compressed = Data(bytes[dataStart..<dataEnd])
                if method == 0 {
                    try? compressed.write(to: entryURL)
                } else if method == 8, let raw = rawDeflate(compressed, uncompressedSize: uSize) {
                    try? raw.write(to: entryURL)
                }
            }
            i = dataEnd
        }
    }
}

// Decompress raw deflate (ZIP method 8) using Compression framework.
private func rawDeflate(_ input: Data, uncompressedSize: Int) -> Data? {
    guard uncompressedSize > 0 else { return Data() }
    var wrapped = Data([0x78, 0x9C])
    wrapped.append(input)
    var output = Data(count: uncompressedSize)
    let written: Int = wrapped.withUnsafeBytes { src in
        output.withUnsafeMutableBytes { dst in
            compression_decode_buffer(
                dst.baseAddress!.assumingMemoryBound(to: UInt8.self),
                uncompressedSize,
                src.baseAddress!.assumingMemoryBound(to: UInt8.self),
                src.count,
                nil,
                COMPRESSION_ZLIB
            )
        }
    }
    guard written > 0 else { return nil }
    return output.prefix(written)
}
