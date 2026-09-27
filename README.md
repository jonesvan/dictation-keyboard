# FindMy BLE Scanner

An iOS SwiftUI app that scans Bluetooth Low Energy advertisements and surfaces
those in Apple's **Find My / Offline Finding** format (manufacturer ID `0x004C`,
type `0x12`). It shows a live-updating list of each packet's timestamp, RSSI,
app-scoped identifier, status byte, and raw payload, with filtering, a
signal-strength bar and history graph, pause/clear controls, and CSV export.

It reads only the public advertisement fields. It does **not** attempt to
decrypt Apple's encrypted location payload, and it never uploads anything — the
rotating key can only be resolved inside Apple's Find My network.

> **No hardware MAC address.** iOS/CoreBluetooth does not expose a peripheral's
> hardware MAC address to third-party apps. The `identifier` shown is a
> per-device, per-app `UUID` that is stable on this device for this app but is
> not the MAC. There is no public API to obtain the MAC.

## Status

This repository contains source and an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec. It has **not been compiled or signed** in the authoring environment (Linux,
no Xcode). Build verification and deployment happen through GitHub Actions.

## Layout

```
DictationKeyboardApp/   The SwiftUI app (scanner, views, CSV export)
project.yml             XcodeGen project spec (source of truth)
.github/workflows/ios.yml   CI: build + optional TestFlight deploy
```

The target/scheme are still named `DictationKeyboardApp` and the bundle IDs are
unchanged so the existing TestFlight pipeline keeps working.

## Features

- Live list keyed by peripheral + payload, so rotating Find My keys appear as new
  rows while repeat sightings update in place (RSSI, timestamp, sighting count).
- Per-packet detail: status byte (hex + binary), 22-byte public key, full
  manufacturer data, and an RSSI-over-time chart.
- Filters: free-text (identifier / payload / status), minimum RSSI slider, and a
  toggle to show all Apple BLE types instead of only `0x12`.
- Pause / resume scanning and clear the captured packets.
- CSV export via the system share sheet.

## Build

Requires macOS with Xcode 15+ and the iOS 17+ SDK.

```sh
brew install xcodegen
xcodegen generate
open DictationKeyboard.xcodeproj
```

Run on a **physical device** — the Simulator does not provide real BLE
advertisements.

## Continuous integration

`.github/workflows/ios.yml` builds the app on a GitHub-hosted macOS runner on
every push and pull request:

- installs XcodeGen, generates the project, and runs `xcodebuild` for the iOS
  Simulator with code signing disabled — a pure compile check.

See `AGENTS.md` for the exact `gh` commands to watch the build and to trigger the
TestFlight upload.

## Permissions

The app declares `NSBluetoothAlwaysUsageDescription`. On first launch iOS asks
for Bluetooth permission; if denied, the in-app banner links straight to
Settings.
