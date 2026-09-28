# AGENTS.md

Guidance for agents working in this repository.

## What this is

An iOS SwiftUI app that scans BLE advertisements using CoreBluetooth and detects
Apple Find My / Offline Finding trackers (AirTags and third-party accessories).
It lists each device's timestamp, RSSI, app-scoped peripheral identifier,
advertised services, and raw advertisement fields, with filtering, a
signal-strength bar/history chart, pause/clear controls, and CSV export. It
never attempts to decrypt Apple's encrypted location data.

**Critical platform fact (do not regress):** iOS does **not** deliver Apple's
Find My manufacturer data (`0x004C`, type `0x12`) to apps — `CBAdvertisementDataManufacturerDataKey`
is stripped for these advertisements (the same reason iBeacon data is
CoreLocation-only). A scanner that waits for that key sees nothing. The correct
approach, used by the published `seemoo-lab/AirGuard-iOS` app, is to treat
*connectable advertisements with no name, no service UUIDs, no service data, and
no manufacturer data* as Find My candidates, then **connect and probe Apple's
Find My GATT services** to confirm
(`7DFC9000-7D1C-4951-86AA-8D9728F8D66C` for AirTags, `FD43` / `87290102-3C51-43B1-A1A9-11B9DC38478B`
for Find My devices). `ApplePacketParser` is kept only for the rare case where
iOS does expose Apple manufacturer data.

Layout:

```
DictationKeyboardApp/   The SwiftUI app (scanner, views, CSV export)
project.yml             XcodeGen spec (source of truth, do NOT hand-edit an .xcodeproj)
.github/workflows/ios.yml   CI: build + optional TestFlight deploy
```

The Xcode target/scheme (`DictationKeyboardApp`) and bundle IDs are kept from
the previous keyboard app so the existing TestFlight pipeline continues to work.

## Environment constraint (important)

This repo is authored on **Linux with no Xcode**. You cannot compile, sign, or
run iOS code locally. Do not attempt `xcodebuild`, `xcodegen`, `swift build`, or
`xcrun` here — they are not installed and will fail or mislead you.

**All build verification and deployment happens through GitHub Actions.** Use
the `gh` CLI (installed) to drive and inspect CI.

## Verify a change (every change)

CI runs automatically on push to `master`/`main` and on PRs. The `build` job
generates the project with XcodeGen and runs a **simulator compile check**
(`CODE_SIGNING_ALLOWED=NO`) — it catches compile errors only, not runtime
behavior. CoreBluetooth does not provide real advertisements in the Simulator,
so runtime behavior must be tested on a device via TestFlight.

Workflow for any code change:

1. Make the edit (edit `project.yml` for target/config changes; never an
   `.xcodeproj`, which is generated and gitignored).
2. Commit and push to `master`.
3. Watch the run and require success:

   ```sh
   gh run list --workflow=ios.yml --limit 5
   gh run watch "$(gh run list --workflow=ios.yml --limit 1 --json databaseId -q '.[0].databaseId')" --exit-status
   ```

Do not report a task as done until the `build` job is green.

## Deploy (TestFlight)

Deployment is the `testflight` job in `.github/workflows/ios.yml`. It runs
**automatically on every push to `master`/`main`** and on manual
`workflow_dispatch` (pull requests are excluded). It depends on `build`
succeeding first, then archives, exports an App Store Connect IPA, and uploads
via `altool`.

To trigger a deploy without a code change:

```sh
gh workflow run "iOS" --ref master
gh run list --workflow=ios.yml --limit 5
gh run watch <run-id> --exit-status
```

Equivalent UI path: **Actions → iOS → Run workflow**.

The archive/export steps need signing and App Store Connect credentials. These
must exist as repository secrets (**Settings → Secrets and variables → Actions**)
and cannot be set by an agent:

| Secret | Purpose |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key ID (used as the `.p8` filename and key ID) |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_CONTENT` | Full contents of the `.p8` private key file |
| `APPLE_TEAM_ID` | 10-character Apple Developer Team ID (also passed as `DEVELOPMENT_TEAM`) |

Other deployment facts:

- Bundle ID is `com.jonesvan.DictationKeyboard` (set in `project.yml`); it is
  unchanged from the original keyboard app so the existing App Store Connect app
  record and TestFlight availability keep working.
- `DEVELOPMENT_TEAM` in `project.yml` is intentionally empty; CI injects it from
  the `APPLE_TEAM_ID` secret during archive.
- `CURRENT_PROJECT_VERSION` is overridden during the CI archive to
  `${{ github.run_number }}.${{ github.run_attempt }}` so every upload gets a
  unique build number; otherwise TestFlight rejects duplicate builds on the same
  version train. The value in `project.yml` only affects local builds.
- `scripts/prune_dev_certs.py` removes stale development certificates before
  archiving; it runs `continue-on-error` and may be skipped safely.
- Signing/provisioning often needs several iterations; treat a failed
  `testflight` job as expected on first runs and read the logs.
- A TestFlight public link requires an enrolled Apple Developer Program membership
  and an existing App Store Connect app record.

## CI gotchas

- `concurrency.group` is `ios-${{ github.ref }}` with `cancel-in-progress: false`
  so an in-flight TestFlight upload is never cancelled by a newer push. Pushes
  queue instead; a third push cancels only the pending (not running) run.
- Node 20 deprecation warnings on `actions/checkout@v4` are harmless.
- Never commit `scripts/__pycache__/`, generated `DictationKeyboard.xcodeproj`,
  or `build/`.

## Code conventions

- Swift 5 language mode (`SWIFT_VERSION: "5.0"`), iOS 17 deployment target.
- Bluetooth permission is declared via `NSBluetoothAlwaysUsageDescription` in
  `DictationKeyboardApp/Info.plist`; without it, constructing a `CBCentralManager`
  crashes. Handle every `CBManagerState` (powered off, unauthorized, unsupported).
- iOS does not expose a peripheral's hardware MAC address; only
  `CBPeripheral.identifier` (an app-scoped UUID) is available. Do not claim a MAC.
- iOS strips Apple's Find My manufacturer data; identify AirTags/Find My devices
  by connecting and probing the GATT services in `FindMyServices`, never by
  expecting `CBAdvertisementDataManufacturerDataKey` for Apple adverts.
- The scanner must never attempt to decrypt Apple's encrypted location payload;
  only decode public advertisement fields (status byte, public key, raw bytes).
- Scanning uses `CBCentralManagerScanOptionAllowDuplicatesKey` so RSSI and
  sighting counts update live.
- Retain `CBPeripheral` references (the `peripherals` dictionary) or delegate
  callbacks for connected candidates stop arriving.
