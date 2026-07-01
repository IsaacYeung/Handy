import Foundation

// Compiled into both the app and the unit-test binary, so the tests exercise
// the real implementation rather than a copy.
enum FileNaming {
    /// Returns a destination URL for `src` inside `dir`, appending " (2)",
    /// " (3)"… to the name until `exists` reports no conflict.
    static func uniqueDestination(
        _ src: URL, in dir: URL,
        exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> URL {
        var dest = dir.appendingPathComponent(src.lastPathComponent)
        guard exists(dest.path) else { return dest }
        let name = src.deletingPathExtension().lastPathComponent
        let ext  = src.pathExtension
        var n = 2
        repeat {
            let candidate = ext.isEmpty ? "\(name) (\(n))" : "\(name) (\(n)).\(ext)"
            dest = dir.appendingPathComponent(candidate)
            n += 1
        } while exists(dest.path)
        return dest
    }
}
