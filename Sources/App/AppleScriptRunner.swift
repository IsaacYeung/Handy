import Foundation

/// Serializes every NSAppleScript execution onto one dedicated queue.
/// NSAppleScript is not safe to use from multiple threads concurrently; a
/// single serial queue removes that hazard while keeping script work off the
/// main run loop, which must stay responsive for the event tap.
final class AppleScriptRunner {
    static let shared = AppleScriptRunner()
    private init() {}

    private let queue = DispatchQueue(label: "com.lonfeng.handy.applescript",
                                      qos: .userInitiated)

    @discardableResult
    func run(_ source: String) -> (descriptor: NSAppleEventDescriptor?, error: NSDictionary?) {
        queue.sync {
            var err: NSDictionary?
            let desc = NSAppleScript(source: source)?.executeAndReturnError(&err)
            return (desc, err)
        }
    }
}
