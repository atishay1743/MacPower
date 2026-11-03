<p align="center">
  <img src="docs/icon.png" width="128" alt="MacPower icon">
</p>

<h1 align="center">MacPower</h1>

<p align="center">
  A tiny menu bar app that shows how many watts your MacBook is pulling, live.
</p>

<p align="center">
  <img src="docs/hero.png" alt="MacPower dropdown while plugged in and on battery" width="720">
</p>

macOS has no built-in live wattage display, so MacPower reads it from IOKit and puts it in the menu bar. The number is always readable at a glance, no clicking needed.

- **Plugged in:** the menu bar shows live charger draw, e.g. `18W`
- **Unplugged:** it shows what the machine is pulling from the battery, as a negative, e.g. `-9W`
- **Click it:** the same figure in large type, plus the system vs. battery split, battery percentage and state. This works in both states, so the dropdown shows the negative draw when you're on battery.

## Install

1. Download `MacPower.dmg` from the [latest release](../../releases/latest), open it, and drag **MacPower** onto **Applications**.

   ![Drag MacPower to Applications](docs/install-1-drag.png)

2. Open MacPower from Applications. macOS will refuse the first time with *“MacPower” Not Opened*. This is expected: the app is not signed with an Apple Developer ID or notarized yet (that costs $99/year), so Gatekeeper blocks any app downloaded outside the App Store that lacks it. Click **Done**.

   ![macOS blocks the first launch](docs/install-2-blocked.png)

3. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to *“MacPower” was blocked to protect your Mac*. Confirm with your password or Touch ID, then click **Open** in the final prompt. You only need to do this once.

   ![Open Anyway in Privacy & Security](docs/install-3-open-anyway.png)

   The *Open Anyway* button only shows for about an hour after the failed launch. If it is gone, open the app once more to bring it back.

Prefer the terminal? One command skips steps 2 and 3:

```bash
xattr -dr com.apple.quarantine /Applications/MacPower.app
```

The wattage should appear in your menu bar right away. Turn on **Open at Login** in the dropdown to keep it running; the login item needs a stable location, so move the app to `/Applications` before enabling it. Quit from the dropdown, or with Cmd+Q while it is open.

If you would rather not bypass Gatekeeper at all, [build it from source](#build-from-source). A copy you build yourself is never quarantined.

> The dropdown image at the top is the app's real view rendered with sample readings. The install images are simplified illustrations; the exact wording and layout of the macOS dialogs vary slightly between versions.

## Build from source

Requires the Xcode Command Line Tools (`xcode-select --install`). Full Xcode is not needed.

```bash
./build.sh
open MacPower.app
```

To build the installer:

```bash
./create-dmg.sh
open MacPower.dmg
```

The DMG contains MacPower and an Applications shortcut for drag-and-drop installation. It is ad-hoc signed; to distribute your own build without the warning above you need a Developer ID signature and notarization.

To regenerate the generated assets (all drawn in code, no design files):

```bash
swift scripts/make-icon.swift            # app icon: flat, Liquid Glass–style tile
swift scripts/make-dmg-background.swift  # installer window gradient and arrow
swift run --package-path scripts/render-docs render-docs   # README images in docs/
```

## Where the numbers come from

All values come from the `AppleSmartBattery` IORegistry entry. No `sudo`, no `powermetrics`, no polling of shell commands.

| Shown as | Source | Units |
| --- | --- | --- |
| Menu bar / adapter draw | `PowerTelemetryData.SystemPowerIn` | mW |
| System | `PowerTelemetryData.SystemLoad` | mW |
| Battery | `PowerTelemetryData.BatteryPower` | mW, negative when draining |
| Adapter rating | `AdapterDetails.Watts` | W |
| Battery percent | `CurrentCapacity` | % |

These are internally consistent: `SystemPowerIn = SystemLoad + BatteryPower`.

Two notes on why it reads these specific keys:

- The **adapter rating** (e.g. `20W`) is the brick's maximum, not what you are using. The menu bar shows real draw instead.
- Battery `Voltage x InstantAmperage` is a tempting shortcut but wrong twice over: it reads ~0 when the battery is full even though the Mac is still pulling wall power, and `InstantAmperage` swings negative mid-charge. It is only used as a fallback on older Macs that do not report `PowerTelemetryData`.

You can cross-check any reading with:

```bash
ioreg -r -c AppleSmartBattery -w0 | grep -o '"SystemPowerIn"=[0-9]*'
```

## Layout

- `Sources/MacPower/PowerMonitor.swift` — IOKit reader, polls once per second
- `Sources/MacPower/MacPowerApp.swift` — `MenuBarExtra` scene
- `Sources/MacPower/StatusMenuView.swift` — dropdown panel and login item toggle
- `Resources/Info.plist` — `LSUIElement` so there is no Dock icon
- `scripts/` — generators for the app icon, DMG background and README images
- `build.sh` — compiles and assembles the `.app` bundle
- `create-dmg.sh` — packages the app into a DMG

Built with SwiftPM rather than an Xcode project so it builds with just the Command Line Tools.

## Requirements

macOS 14 or later, on a Mac with a battery. Apple silicon reports the full telemetry set; Intel Macs fall back to battery voltage and current.

## Contributing

Issues and pull requests are welcome. If a reading looks wrong on your Mac, include the output of `ioreg -r -c AppleSmartBattery -w0` and your Mac model.

## License

[MIT](LICENSE)
