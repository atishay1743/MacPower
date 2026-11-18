import AppKit
import Combine
import SwiftUI

@main
enum MacPowerApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = MacPowerDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class MacPowerDelegate: NSObject, NSApplicationDelegate {
    private let settings = MacPowerSettings()
    private lazy var monitor = PowerMonitor(chargerOnly: settings.chargerOnly)
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var settingsWindow: NSWindow?
    private var statusUpdates: AnyCancellable?
    private var chargerOnlyUpdates: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        statusItem = item

        popover.behavior = .transient
        let content = NSHostingController(rootView: StatusMenuView(monitor: monitor) { [weak self] in
            self?.openSettings()
        })
        content.sizingOptions.insert(.preferredContentSize)
        popover.contentViewController = content

        chargerOnlyUpdates = settings.$chargerOnly.removeDuplicates().sink { [weak self] enabled in
            self?.monitor.setChargerOnly(enabled)
        }
        statusUpdates = monitor.$snapshot.combineLatest(settings.$menuBarDisplay, settings.$chargerOnly)
            .sink { [weak self] snapshot, display, chargerOnly in
                self?.updateStatusItem(snapshot: snapshot, display: display, chargerOnly: chargerOnly)
            }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func updateStatusItem(snapshot: PowerSnapshot, display: MenuBarDisplay, chargerOnly: Bool) {
        let visible = !chargerOnly || snapshot.isPluggedIn
        if !visible { popover.close() }
        let title = display.title(for: snapshot)
        let button = statusItem?.button
        button?.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ])
        button?.setAccessibilityLabel("MacPower, \(display.label): \(title)")
        button?.toolTip = "MacPower · \(display.label)"
        statusItem?.isVisible = visible
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem?.button {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func openSettings() {
        popover.close()
        let window: NSWindow
        if let settingsWindow {
            window = settingsWindow
        } else {
            window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
            window.title = "MacPower Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }
}
