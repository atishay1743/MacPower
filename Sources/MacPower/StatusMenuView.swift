import ServiceManagement
import SwiftUI

struct StatusMenuView: View {
    @ObservedObject var monitor: PowerMonitor

    @State private var openAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginItemError: String?

    private var snapshot: PowerSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline

            if snapshot.hasBattery {
                VStack(alignment: .leading, spacing: 6) {
                    detail("System", watts: snapshot.systemWatts)
                    detail("Battery", watts: snapshot.batteryWatts, signed: true)
                }
            }

            batteryLine

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                usageDetail("CPU", value: snapshot.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "--")
                    .help("Overall CPU usage across all cores, averaged since the previous reading.")
                usageDetail("RAM", value: memoryUsage)
                    .help("Memory used by apps, wired memory and compressed memory, excluding caches.")
            }

            Divider()

            HStack {
                Toggle("Open at Login", isOn: $openAtLogin)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .onChange(of: openAtLogin) { _, isOn in
                        setOpenAtLogin(isOn)
                    }

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut("q")
                .help("Quit MacPower")
                .accessibilityLabel("Quit MacPower")
            }

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 240, alignment: .leading)
    }

    @ViewBuilder
    private var headline: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !snapshot.hasBattery {
                Text("No battery")
                    .font(.title2.weight(.semibold))
                Text("MacPower needs a MacBook")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if snapshot.isPluggedIn {
                Text(format(snapshot.adapterWatts) ?? "--")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(adapterCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // Same figure as the menu bar: what the Mac pulls from the
                // battery, shown negative.
                Text(format(snapshot.systemWatts.map { -abs($0) }) ?? "--")
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Drawing from battery")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var adapterCaption: String {
        var parts = ["Drawing from charger"]
        if let rated = snapshot.adapterRatedWatts {
            parts.append("\(rated)W adapter")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var batteryLine: some View {
        if snapshot.hasBattery, let percent = snapshot.batteryPercent {
            HStack(spacing: 4) {
                Text("Battery")
                Spacer()
                Text("\(percent)% · \(batteryState)")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var batteryState: String {
        if snapshot.isCharging { return "Charging" }
        if snapshot.isFullyCharged { return "Charged" }
        return snapshot.isPluggedIn ? "On adapter" : "Discharging"
    }

    private func detail(_ label: String, watts: Double?, signed: Bool = false) -> some View {
        usageDetail(label, value: format(watts, signed: signed) ?? "--")
    }

    private var memoryUsage: String {
        guard let used = snapshot.memoryUsedBytes, let total = snapshot.memoryTotalBytes else { return "--" }
        let gigabyte = 1_073_741_824.0
        return String(format: "%.1f / %.0f GB", Double(used) / gigabyte, Double(total) / gigabyte)
    }

    private func usageDetail(_ label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func format(_ watts: Double?, signed: Bool = false) -> String? {
        guard let watts else { return nil }
        let sign = signed && watts > 0.05 ? "+" : ""
        return String(format: "\(sign)%.1f W", watts)
    }

    private func setOpenAtLogin(_ isOn: Bool) {
        do {
            if isOn {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            openAtLogin = !isOn
            loginItemError = "Could not update login item. Move MacPower to /Applications and try again."
        }
    }
}
