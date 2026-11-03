import AppKit
import SwiftUI

// Renders the README images into docs/. The dropdown is the app's real
// StatusMenuView; the install steps are simplified illustrations.

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let docs = root.appendingPathComponent("docs")
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

func writePNG(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: docs.appendingPathComponent(name))
    print("Wrote docs/\(name)")
}

/// Renders pure-SwiftUI content.
@MainActor
func render<V: View>(_ view: V, name: String) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    let cg = renderer.cgImage!
    writePNG(NSBitmapImageRep(cgImage: cg), name)
}

/// Renders content that contains AppKit-backed controls (the login switch),
/// which ImageRenderer cannot draw.
@MainActor
func renderHosted<V: View>(_ view: V) -> NSImage {
    let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
    host.frame = CGRect(origin: .zero, size: host.fittingSize)
    let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: .darkAqua)
    window.backgroundColor = .clear
    window.isOpaque = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
    host.cacheDisplay(in: host.bounds, to: rep)
    let image = NSImage(size: host.bounds.size)
    image.addRepresentation(rep)
    return image
}

// MARK: - Shared pieces

struct Backdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(hex: 0xE4501C), Color(hex: 0xF5A21F)],
            startPoint: .bottomLeading, endPoint: .topTrailing)
    }
}

let appIcon = NSImage(contentsOf: root.appendingPathComponent("Resources/AppIcon.png"))!
let folderIcon = NSWorkspace.shared.icon(forFile: "/Applications")

struct Panel: View {
    let monitor: PowerMonitor
    var body: some View {
        StatusMenuView(monitor: monitor)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
    }
}

// MARK: - Readings

var plugged = PowerSnapshot()
plugged.hasBattery = true
plugged.isPluggedIn = true
plugged.isCharging = true
plugged.batteryPercent = 64
plugged.adapterWatts = 18.3
plugged.adapterRatedWatts = 20
plugged.systemWatts = 7.2
plugged.batteryWatts = 11.1

var unplugged = PowerSnapshot()
unplugged.hasBattery = true
unplugged.batteryPercent = 71
unplugged.systemWatts = 9.4
unplugged.batteryWatts = -9.4

// MARK: - Hero: the dropdown in both states

struct Column: View {
    let title: String
    let menuBar: String
    let panel: NSImage
    var body: some View {
        VStack(spacing: 14) {
            Text(menuBar)
                .font(.system(size: 14, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            Image(nsImage: panel)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.top, 6)
        }
    }
}

@MainActor
func renderHero() {
    let pluggedPanel = renderHosted(Panel(monitor: PowerMonitor(fixed: plugged)))
    let unpluggedPanel = renderHosted(Panel(monitor: PowerMonitor(fixed: unplugged)))
    render(
        ZStack {
            Backdrop()
            HStack(alignment: .top, spacing: 56) {
                Column(title: "Plugged in", menuBar: "18W", panel: pluggedPanel)
                Column(title: "On battery", menuBar: "-9W", panel: unpluggedPanel)
            }
        }
        .frame(width: 720, height: 400),
        name: "hero.png")
}

// MARK: - Install steps

struct StepFrame<Content: View>: View {
    let number: Int
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: .topLeading) {
            Backdrop()
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("\(number)")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(Color(hex: 0xC23A0E))
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
                .padding(18)
        }
        .frame(width: 720, height: 340)
    }
}

struct DragStep: View {
    var body: some View {
        StepFrame(number: 1) {
            HStack(spacing: 64) {
                VStack(spacing: 10) {
                    Image(nsImage: appIcon).resizable().frame(width: 116, height: 116)
                    Text("MacPower").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                VStack(spacing: 10) {
                    Image(nsImage: folderIcon).resizable().frame(width: 116, height: 116)
                    Text("Applications").font(.system(size: 14, weight: .medium)).foregroundStyle(.white)
                }
            }
        }
    }
}

struct BlockedStep: View {
    var body: some View {
        StepFrame(number: 2) {
            VStack(spacing: 14) {
                Image(nsImage: appIcon).resizable().frame(width: 64, height: 64)
                Text("“MacPower” Not Opened")
                    .font(.system(size: 15, weight: .bold))
                Text("Apple could not verify “MacPower” is free of malware that may harm your Mac or compromise your privacy.")
                    .font(.system(size: 12.5))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                VStack(spacing: 8) {
                    Text("Done")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x3B82F6)))
                    Text("Move to Trash")
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.14)))
                }
                .padding(.top, 4)
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(width: 300)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.17)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}

struct OpenAnywayStep: View {
    var body: some View {
        StepFrame(number: 3) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy & Security")
                    .font(.system(size: 17, weight: .bold))
                Text("Security")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
                HStack(spacing: 12) {
                    Text("“MacPower” was blocked to protect your Mac.")
                        .font(.system(size: 13))
                    Spacer(minLength: 8)
                    Text("Open Anyway")
                        .font(.system(size: 13, weight: .medium))
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x3B82F6)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color(hex: 0xFFD21F), lineWidth: 2.5)
                                .padding(-5))
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
            }
            .foregroundStyle(.white)
            .padding(24)
            .frame(width: 520)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(white: 0.17)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
        }
    }
}


// MARK: - Menu bar strip

struct MenuBarRow: View {
    let value: String
    let caption: String
    var body: some View {
        HStack(spacing: 16) {
            Text(caption)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 92, alignment: .leading)
            HStack(spacing: 14) {
                Image(systemName: "applelogo")
                Text("Finder").fontWeight(.semibold)
                Text("File")
                Text("Edit")
                Spacer(minLength: 0)
                Text(value)
                    .monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.22)))
                Image(systemName: "wifi")
                Image(systemName: "battery.75percent")
                Text("Tue 9:41")
            }
            .font(.system(size: 13))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(width: 470, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.black.opacity(0.42)))
        }
    }
}

@MainActor
func renderMenuBar() {
    render(
        ZStack {
            Backdrop()
            VStack(alignment: .leading, spacing: 18) {
                MenuBarRow(value: "18W", caption: "Plugged in")
                MenuBarRow(value: "-9W", caption: "On battery")
            }
        }
        .frame(width: 720, height: 150),
        name: "menubar.png")
}

MainActor.assumeIsolated {
    renderHero()
    renderMenuBar()
    render(DragStep(), name: "install-1-drag.png")
    render(BlockedStep(), name: "install-2-blocked.png")
    render(OpenAnywayStep(), name: "install-3-open-anyway.png")
}
