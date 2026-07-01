import Foundation

final class KeepAwake {
    static let shared = KeepAwake()
    private init() {}

    private var process: Process?

    var isActive: Bool { process?.isRunning == true }

    func enable() {
        guard !isActive else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        // -d prevents display sleep, -i prevents idle sleep
        p.arguments = ["-d", "-i"]
        try? p.run()
        process = p
    }

    func disable() {
        process?.terminate()
        process = nil
    }

    func toggle() {
        isActive ? disable() : enable()
    }
}
