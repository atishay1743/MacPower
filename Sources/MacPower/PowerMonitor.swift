import Foundation
import IOKit
import IOKit.ps

/// One reading of the Mac's power state.
///
/// Watt values are signed: `batteryWatts` is positive while the battery charges
/// and negative while it drains.
struct PowerSnapshot: Equatable {
    var hasBattery = false
    var isPluggedIn = false
    var isCharging = false
    var isFullyCharged = false
    var batteryPercent: Int?

    /// Live power drawn from the charger.
    var adapterWatts: Double?
    /// Maximum the connected charger advertises.
    var adapterRatedWatts: Int?
    /// Power the machine itself is consuming.
    var systemWatts: Double?
    var batteryWatts: Double?

    /// Always-visible menu bar text: charger draw when plugged in, otherwise
    /// what the machine is pulling from the battery, shown as negative.
    /// A missing value shows "--" rather than a number from the wrong state.
    var menuBarTitle: String {
        guard hasBattery else { return "--" }
        if isPluggedIn {
            return adapterWatts.map { String(format: "%.0fW", $0) } ?? "--"
        }
        return systemWatts.map { String(format: "-%.0fW", $0) } ?? "--"
    }
}

final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot()

    private let smc: SMCReader?
    private var timer: Timer?
    private var powerSourceLoop: CFRunLoopSource?

    init() {
        smc = SMCReader()
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Common mode keeps readings live while the menu bar panel is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        observePowerSourceChanges()
    }

    /// A monitor frozen on one reading, with no polling. For previews and
    /// rendering docs images.
    init(fixed snapshot: PowerSnapshot) {
        smc = nil
        self.snapshot = snapshot
    }

    deinit {
        timer?.invalidate()
        if let powerSourceLoop {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSourceLoop, .commonModes)
        }
    }

    func refresh() {
        let next = read()
        if next != snapshot {
            snapshot = next
        }
    }

    /// The system tells us the instant a charger is plugged or unplugged, so
    /// react then instead of waiting for the next tick. The sensors need a
    /// moment to settle after the switch, so follow up with a few quick reads.
    private func observePowerSourceChanges() {
        let callback: IOPowerSourceCallbackType = { context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().powerSourceChanged()
        }
        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource(callback, context)?.takeRetainedValue() else { return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceLoop = source
    }

    private func powerSourceChanged() {
        refresh()
        for delay in [0.25, 0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refresh()
            }
        }
    }

    private func read() -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        guard let properties = Self.batteryProperties() else { return snapshot }

        snapshot.hasBattery = (properties["BatteryInstalled"] as? Bool) ?? true
        snapshot.isPluggedIn = Self.isOnExternalPower() ?? (properties["ExternalConnected"] as? Bool) ?? false
        snapshot.isCharging = (properties["IsCharging"] as? Bool) ?? false
        snapshot.isFullyCharged = (properties["FullyCharged"] as? Bool) ?? false
        snapshot.batteryPercent = (properties["CurrentCapacity"] as? NSNumber)?.intValue

        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            snapshot.adapterRatedWatts = (adapter["Watts"] as? NSNumber)?.intValue
        }

        if let live = smc?.readPower() {
            Self.apply(live, to: &snapshot)
        } else {
            Self.applyRegistryEstimate(properties, to: &snapshot)
        }

        // A charger that is connected always delivers something. Zero means
        // the sensors have not caught up with the plug yet, so show nothing
        // rather than a wrong 0.
        if snapshot.isPluggedIn, let watts = snapshot.adapterWatts, watts < 0.5 {
            snapshot.adapterWatts = nil
        }

        return snapshot
    }

    /// Real-time path, from SMC sensors.
    private static func apply(_ live: SMCReader.Power, to snapshot: inout PowerSnapshot) {
        snapshot.systemWatts = max(live.system, 0)
        if snapshot.isPluggedIn {
            snapshot.adapterWatts = max(live.adapter, 0)
            snapshot.batteryWatts = live.battery ?? (live.adapter - live.system)
        } else {
            // Nothing comes from the charger, so the battery supplies it all.
            snapshot.batteryWatts = -abs(live.battery ?? live.system)
        }
    }

    /// Fallback for Macs without these SMC sensors. The registry values are
    /// refreshed only every 20 to 60 seconds, so they lag behind a plug or
    /// unplug. Each value is used only if it fits the current plug state.
    private static func applyRegistryEstimate(_ properties: [String: Any], to snapshot: inout PowerSnapshot) {
        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
            snapshot.systemWatts = milliValue(telemetry["SystemLoad"]).map { $0 / 1000 }
            snapshot.batteryWatts = milliValue(telemetry["BatteryPower"]).map { $0 / 1000 }
            if snapshot.isPluggedIn {
                snapshot.adapterWatts = adapterWatts(telemetry: telemetry)
            }
        }

        // Voltage x current is a rough stand-in. InstantAmperage swings
        // negative even mid-charge, so prefer the averaged Amperage.
        if snapshot.batteryWatts == nil,
           let millivolts = milliValue(properties["Voltage"]),
           let milliamps = milliValue(properties["Amperage"] ?? properties["InstantAmperage"]) {
            snapshot.batteryWatts = millivolts * milliamps / 1_000_000
        }

        // Intel Macs predate PowerTelemetryData, so fall back to what the
        // battery reports about the charge going into it.
        if snapshot.adapterWatts == nil, snapshot.isPluggedIn, let battery = snapshot.batteryWatts {
            snapshot.adapterWatts = max(battery, 0)
        }

        // Plugged in, the battery draws nothing; on battery, the system load
        // is the battery drain. Take the sign from the plug state, because a
        // stale reading may carry the wrong one.
        if !snapshot.isPluggedIn, let battery = snapshot.batteryWatts {
            snapshot.batteryWatts = -abs(battery)
            snapshot.systemWatts = snapshot.systemWatts ?? abs(battery)
        }
    }

    /// Whether the Mac is running on a charger right now. Unlike the battery
    /// registry entry, this is updated the moment the cable moves.
    private static func isOnExternalPower() -> Bool? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() as String? else { return nil }
        return type == kIOPSACPowerValue
    }

    private static func adapterWatts(telemetry: [String: Any]) -> Double? {
        if let milliwatts = milliValue(telemetry["SystemPowerIn"]), milliwatts > 0 {
            return milliwatts / 1000
        }
        if let millivolts = milliValue(telemetry["SystemVoltageIn"]),
           let milliamps = milliValue(telemetry["SystemCurrentIn"]) {
            let watts = millivolts * milliamps / 1_000_000
            if watts > 0 { return watts }
        }
        return nil
    }

    private static func batteryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let properties = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return properties
    }

    /// IOKit reports negative readings as unsigned integers, so discharge
    /// arrives as a value near 2^64 or 2^32. Reinterpret those as negative.
    private static func milliValue(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.uint64Value
        if raw > UInt64(Int64.max) {
            return Double(Int64(bitPattern: raw))
        }
        if raw > UInt64(Int32.max), raw <= UInt64(UInt32.max) {
            return Double(Int32(bitPattern: UInt32(raw)))
        }
        return Double(raw)
    }
}
