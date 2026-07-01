import Foundation
import AppKit

// MARK: - Bluetooth power via IOBluetooth private API
// IOBluetoothPreferenceSet/GetControllerPowerState are private but stable
// and used by many macOS utilities (blueutil, etc.)

final class BluetoothManager {
    static let shared = BluetoothManager()
    private init() {}

    private typealias GetFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32) -> Void

    private let handle: UnsafeMutableRawPointer? =
        dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_NOW)

    var isAvailable: Bool {
        guard let h = handle else { return false }
        return dlsym(h, "IOBluetoothPreferenceSetControllerPowerState") != nil
    }

    var isPoweredOn: Bool {
        guard let h = handle,
              let sym = dlsym(h, "IOBluetoothPreferenceGetControllerPowerState")
        else { return false }
        return unsafeBitCast(sym, to: GetFn.self)() != 0
    }

    func setPower(_ on: Bool) {
        guard let h = handle,
              let sym = dlsym(h, "IOBluetoothPreferenceSetControllerPowerState")
        else { return }
        unsafeBitCast(sym, to: SetFn.self)(on ? 1 : 0)
    }
}

// MARK: - Sleep/wake observer

final class BluetoothSleepFeature {
    static let shared = BluetoothSleepFeature()
    private init() {}

    private var wasOnBeforeSleep = false
    private var observing = false

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "feature.btOffOnSleep") }
        set {
            UserDefaults.standard.set(newValue, forKey: "feature.btOffOnSleep")
            newValue ? startObserving() : stopObserving()
        }
    }

    func startIfEnabled() {
        if isEnabled { startObserving() }
    }

    private func startObserving() {
        guard !observing else { return }
        observing = true
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(willSleep),
                       name: NSWorkspace.willSleepNotification, object: nil)
        nc.addObserver(self, selector: #selector(didWake),
                       name: NSWorkspace.didWakeNotification, object: nil)
    }

    private func stopObserving() {
        guard observing else { return }
        observing = false
        let nc = NSWorkspace.shared.notificationCenter
        nc.removeObserver(self, name: NSWorkspace.willSleepNotification, object: nil)
        nc.removeObserver(self, name: NSWorkspace.didWakeNotification, object: nil)
    }

    @objc private func willSleep() {
        wasOnBeforeSleep = BluetoothManager.shared.isPoweredOn
        if wasOnBeforeSleep {
            BluetoothManager.shared.setPower(false)
        }
    }

    @objc private func didWake() {
        if wasOnBeforeSleep {
            BluetoothManager.shared.setPower(true)
            wasOnBeforeSleep = false
        }
    }

    // Called at app termination: if we turned Bluetooth off for sleep and the
    // wake handler never ran, turn it back on rather than leaving it off.
    func restoreOnQuit() {
        if wasOnBeforeSleep {
            BluetoothManager.shared.setPower(true)
            wasOnBeforeSleep = false
        }
    }
}
