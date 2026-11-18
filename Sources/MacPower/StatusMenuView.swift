import SwiftUI

struct StatusMenuView: View {
    static let width: CGFloat = 264
    static let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)

    @ObservedObject var monitor: PowerMonitor
    let onSettings: () -> Void

    private var snapshot: PowerSnapshot { monitor.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headline
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if snapshot.hasBattery {
                VStack(alignment: .leading, spacing: 6) {
                    detail("System", watts: snapshot.systemWatts)
                    detail("Battery", watts: snapshot.batteryWatts, signed: true)
                }
            }

            if snapshot.hasBattery {
                VStack(spacing: 6) {
                    batteryLine

                    if let time = snapshot.chargeTime {
                        usageDetail("Time to full", value: time)
                            .help("Estimated charging time. It can change as the charging rate changes.")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                usageDetail("CPU", value: snapshot.cpuPercent.map { String(format: "%.1f%%", $0) } ?? "--")
                    .help("Overall CPU usage across all cores, averaged since the previous reading.")
                usageDetail("RAM", value: memoryUsage)
                    .help("Memory used by apps, wired memory and compressed memory, excluding caches.")
            }

            HStack {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                }
                .keyboardShortcut(",")
                .help("Settings")
                .accessibilityLabel("Settings")

                Spacer()

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Image(systemName: "power")
                }
                .keyboardShortcut("q")
                .help("Quit MacPower")
                .accessibilityLabel("Quit MacPower")
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.roundedRectangle(radius: 9))
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .background(.regularMaterial, in: Self.shape)
        .overlay { Self.shape.strokeBorder(Color.primary.opacity(0.12)).allowsHitTesting(false) }
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
                // Power drawn from the battery is shown as negative.
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
        if let percent = snapshot.batteryPercent {
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
}
