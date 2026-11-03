import Foundation
import IOKit

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
    var menuBarTitle: String {
        guard hasBattery else { return "--" }
        if isPluggedIn, let watts = adapterWatts {
            return String(format: "%.0fW", watts)
        }
        if let watts = systemWatts {
            return String(format: "-%.0fW", watts)
        }
        return "--"
    }
}

final class PowerMonitor: ObservableObject {
    @Published private(set) var snapshot = PowerSnapshot()

    private var timer: Timer?

    init() {
        refresh()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Common mode keeps readings live while the menu bar panel is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    deinit {
        timer?.invalidate()
    }

    func refresh() {
        let next = Self.read()
        if next != snapshot {
            snapshot = next
        }
    }

    private static func read() -> PowerSnapshot {
        var snapshot = PowerSnapshot()
        guard let properties = batteryProperties() else { return snapshot }

        snapshot.hasBattery = (properties["BatteryInstalled"] as? Bool) ?? true
        snapshot.isPluggedIn = (properties["ExternalConnected"] as? Bool) ?? false
        snapshot.isCharging = (properties["IsCharging"] as? Bool) ?? false
        snapshot.isFullyCharged = (properties["FullyCharged"] as? Bool) ?? false
        snapshot.batteryPercent = (properties["CurrentCapacity"] as? NSNumber)?.intValue

        if let adapter = properties["AdapterDetails"] as? [String: Any] {
            snapshot.adapterRatedWatts = (adapter["Watts"] as? NSNumber)?.intValue
        }

        let telemetry = properties["PowerTelemetryData"] as? [String: Any]

        if let telemetry {
            snapshot.systemWatts = milliValue(telemetry["SystemLoad"]).map { $0 / 1000 }
            snapshot.batteryWatts = milliValue(telemetry["BatteryPower"]).map { $0 / 1000 }
            snapshot.adapterWatts = adapterWatts(telemetry: telemetry)
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

        return snapshot
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
