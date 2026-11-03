import SwiftUI

@main
struct MacPowerApp: App {
    @StateObject private var monitor = PowerMonitor()

    var body: some Scene {
        MenuBarExtra {
            StatusMenuView(monitor: monitor)
        } label: {
            // A Label renders icon-only in the menu bar, so use plain text to
            // keep the wattage readable without opening the panel.
            Text(monitor.snapshot.menuBarTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)
    }
}
