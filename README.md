# FindMy BLE Scanner

An iOS SwiftUI app that scans Bluetooth Low Energy advertisements and detects
Apple **Find My / Offline Finding** trackers (AirTags and third-party
accessories). It shows a live-updating list of each device's timestamp, RSSI,
app-scoped identifier, advertised services, and raw advertisement fields, with
filtering, a signal-strength bar and history graph, pause/clear controls, and
CSV export.

It reads only public advertisement fields. It does **not** attempt to decrypt
Apple's encrypted location payload, and it never uploads anything — the rotating
key can only be resolved inside Apple's Find My network.

> **How detection actually works on iOS.** iOS strips Apple's Find My
> manufacturer data (`0x004C`, type `0x12`) from advertisements delivered to
> apps, so a scanner that waits for `CBAdvertisementDataManufacturerDataKey` sees
> nothing. The app instead follows the approach used by
> [seemoo-lab/AirGuard-iOS](https://github.com/seemoo-lab/AirGuard-iOS): treat
> *connectable advertisements with no name, no service UUIDs, no service data,
> and no manufacturer data* as candidates, then connect and probe Apple's Find My
> GATT services (`7DFC9000-7D1C-4951-86AA-8D9728F8D66C` for AirTags; `FD43` and
> `87290102-3C51-43B1-A1A9-11B9DC38478B` for Find My devices) to confirm.

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

- Live list of every BLE device seen, categorised as confirmed AirTag / Find My
  device, Find My candidate (being probed), Apple advertisement, or generic BLE
  device.
- Automatic connect-and-probe of Find My candidates to confirm AirTags / Find My
  accessories, with the matching GATT service shown.
- Per-device detail: category, advertised services, manufacturer data (when iOS
  exposes it), Apple status byte / public key when present, and an RSSI chart.
- Filters: free-text (identifier / name / service / category), minimum RSSI
  slider, and a toggle to show all BLE devices instead of only Find My related.
- Pause / resume scanning and clear the captured devices.
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
