import AppKit
import SwiftUI

@MainActor
final class StatusPanel: NSPanel, NSWindowDelegate {
    private let host: NSHostingController<StatusMenuView>

    init(content: StatusMenuView) {
        host = NSHostingController(rootView: content)
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        contentViewController = host
        delegate = self
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isFloatingPanel = true
        hidesOnDeactivate = true
        level = .popUpMenu
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    func position(below button: NSStatusBarButton, clickLocation: NSPoint? = nil) -> Bool {
        guard let (anchor, screen) = menuBarAnchor(for: button, clickLocation: clickLocation) else { return false }
        let size = host.sizeThatFits(in: NSSize(width: StatusMenuView.width, height: .greatestFiniteMagnitude))
        let nextFrame = Self.frame(size: size, anchor: anchor, visibleScreen: screen.visibleFrame)
        if frame != nextFrame {
            setFrame(nextFrame, display: true)
            invalidateShadow()
        }
        return true
    }

    private func menuBarAnchor(for button: NSStatusBarButton, clickLocation: NSPoint?) -> (NSRect, NSScreen)? {
        if let window = button.window, let screen = window.screen {
            let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
            if screen.frame.contains(NSPoint(x: anchor.midX, y: anchor.midY)),
               anchor.minY >= screen.visibleFrame.maxY - anchor.height {
                return (anchor, screen)
            }
        }

        // The status window can briefly report an off-screen frame as the menu bar moves.
        guard let clickLocation, let screen = NSScreen.screens.first(where: { $0.frame.contains(clickLocation) }) else { return nil }
        let bottom = min(screen.visibleFrame.maxY, screen.frame.maxY - NSStatusBar.system.thickness)
        guard clickLocation.y >= bottom else { return nil }
        return (NSRect(x: clickLocation.x, y: bottom, width: 0, height: 0), screen)
    }

    static func frame(size: NSSize, anchor: NSRect, visibleScreen: NSRect) -> NSRect {
        let sideInset: CGFloat = 6
        let left = visibleScreen.minX + sideInset
        let right = max(left, visibleScreen.maxX - size.width - sideInset)
        let x = min(max(anchor.midX - size.width / 2, left), right)
        let y = min(anchor.minY, visibleScreen.maxY) - size.height - 3
        return NSRect(origin: NSPoint(x: x, y: y), size: size)
    }

    func windowDidResignKey(_ notification: Notification) {
        orderOut(nil)
    }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }
}
