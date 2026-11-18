import ServiceManagement
import SwiftUI

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case power, batteryVoltage, timeToFull

    var id: Self { self }

    var label: String {
        switch self {
        case .power: "Power (W)"
        case .batteryVoltage: "Battery Voltage (V)"
        case .timeToFull: "Time to Full"
        }
    }

    func title(for snapshot: PowerSnapshot) -> String {
        switch self {
        case .power:
            return snapshot.menuBarPower
        case .batteryVoltage:
            return snapshot.batteryVoltage.map { String(format: "%.1fV", $0) } ?? "—"
        case .timeToFull:
            if snapshot.isFullyCharged { return "Full" }
            return snapshot.chargeTime ?? "—"
        }
    }
}

final class MacPowerSettings: ObservableObject {
    private let defaults: UserDefaults

    @Published var menuBarDisplay: MenuBarDisplay {
        didSet { defaults.set(menuBarDisplay.rawValue, forKey: "menuBarDisplay") }
    }

    @Published var chargerOnly: Bool {
        didSet { defaults.set(chargerOnly, forKey: "chargerOnly") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        menuBarDisplay = defaults.string(forKey: "menuBarDisplay").flatMap(MenuBarDisplay.init(rawValue:)) ?? .power
        chargerOnly = defaults.bool(forKey: "chargerOnly")
    }
}

struct SettingsView: View {
    @ObservedObject var settings: MacPowerSettings
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var loginItemError: String?

    private var openAtLogin: Binding<Bool> {
        Binding(
            get: { loginStatus == .enabled || loginStatus == .requiresApproval },
            set: setOpenAtLogin
        )
    }

    var body: some View {
        Form {
            Section("Menu Bar") {
                Picker("Show in Menu Bar", selection: $settings.menuBarDisplay) {
                    ForEach(MenuBarDisplay.allCases) { display in
                        Text(display.label).tag(display)
                    }
                }
                if settings.menuBarDisplay == .timeToFull {
                    Text("An estimate appears while the battery is charging.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Toggle("Only when plugged in", isOn: $settings.chargerOnly)
                    .toggleStyle(.switch)
                Text("Hides MacPower and pauses readings on battery. Reopen MacPower from Applications to change this while hidden.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Startup") {
                Toggle("Open at Login", isOn: openAtLogin)
                    .toggleStyle(.switch)
                if loginStatus == .requiresApproval {
                    Button("Open Login Items in System Settings") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }
                if let loginItemError {
                    Text(loginItemError)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 440)
        .onAppear { loginStatus = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    private func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Could not update Open at Login. Move MacPower to Applications and try again."
        }
        loginStatus = SMAppService.mainApp.status
    }
}
