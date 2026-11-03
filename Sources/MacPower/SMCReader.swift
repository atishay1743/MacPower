import Foundation
import IOKit

/// Live power sensors from the System Management Controller.
///
/// The `AppleSmartBattery` registry entry is a cache the system refreshes only
/// every 20 to 60 seconds, so around a plug or unplug it still holds the
/// previous state. The SMC is where those numbers originate, and reading it
/// directly is live. It needs no sudo.
final class SMCReader {
    struct Power {
        /// Watts flowing in from the charger (`PDTR`). Near zero on battery.
        var adapter: Double
        /// Watts the whole machine is using (`PSTR`).
        var system: Double
        /// Watts into (+) or out of (-) the battery (`PPBR`), if the key exists.
        var battery: Double?
    }

    // These mirror the C struct behind the AppleSMC user client. The explicit
    // padding matters: Swift packs a struct's tail padding, C does not, and the
    // kernel rejects a misplaced field with kIOReturnBadArgument.
    private struct Version {
        var major: UInt8 = 0, minor: UInt8 = 0, build: UInt8 = 0, reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct PLimit {
        var version: UInt16 = 0, length: UInt16 = 0
        var cpu: UInt32 = 0, gpu: UInt32 = 0, mem: UInt32 = 0
    }

    private struct KeyInfo {
        var size: UInt32 = 0, type: UInt32 = 0
        var attributes: UInt8 = 0
        var pad: (UInt8, UInt8, UInt8) = (0, 0, 0)
    }

    private struct KeyData {
        var key: UInt32 = 0
        var version = Version()
        var pLimit = PLimit()
        var info = KeyInfo()
        var result: UInt8 = 0, status: UInt8 = 0, command: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt64, UInt64, UInt64, UInt64) = (0, 0, 0, 0)
    }

    private static let handleEvent: UInt32 = 2
    private static let readBytes: UInt8 = 5
    private static let readKeyInfo: UInt8 = 9
    private static let floatType = fourCC("flt ")

    private var connection: io_connect_t = 0

    /// Nil when the SMC cannot be opened, such as inside a sandbox.
    init?() {
        guard MemoryLayout<KeyData>.stride == 80 else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }
        guard IOServiceOpen(service, mach_task_self_, 0, &connection) == KERN_SUCCESS else { return nil }
    }

    deinit {
        IOServiceClose(connection)
    }

    /// One live reading, or nil if the machine lacks these sensors.
    func readPower() -> Power? {
        guard let adapter = float("PDTR"), let system = float("PSTR") else { return nil }
        return Power(adapter: adapter, system: system, battery: float("PPBR"))
    }

    private func float(_ key: String) -> Double? {
        var request = KeyData()
        request.key = Self.fourCC(key)
        request.command = Self.readKeyInfo
        guard let info = call(&request), info.info.type == Self.floatType, info.info.size == 4 else { return nil }

        request = KeyData()
        request.key = Self.fourCC(key)
        request.info.size = info.info.size
        request.command = Self.readBytes
        guard let reply = call(&request) else { return nil }

        let value = withUnsafeBytes(of: reply.bytes) { $0.loadUnaligned(as: Float.self) }
        return value.isFinite ? Double(value) : nil
    }

    private func call(_ input: inout KeyData) -> KeyData? {
        var output = KeyData()
        var outputSize = MemoryLayout<KeyData>.stride
        let status = IOConnectCallStructMethod(
            connection, Self.handleEvent,
            &input, MemoryLayout<KeyData>.stride,
            &output, &outputSize
        )
        return status == KERN_SUCCESS && output.result == 0 ? output : nil
    }

    private static func fourCC(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { $0 << 8 | UInt32($1) }
    }
}
