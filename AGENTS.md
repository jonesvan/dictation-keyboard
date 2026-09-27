# AGENTS.md

Guidance for agents working in this repository.

## What this is

An iOS SwiftUI app that scans BLE advertisements using CoreBluetooth and lists
those matching Apple's Find My / Offline Finding format (manufacturer ID
`0x004C`, type `0x12`). It shows each packet's timestamp, RSSI, app-scoped
peripheral identifier, status byte, and raw payload, with filtering, a
signal-strength bar/history chart, pause/clear controls, and CSV export. It
never attempts to decrypt Apple's encrypted location data.

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

Deployment is the `testflight` job in `.github/workflows/ios.yml`. It only runs
on a **manual `workflow_dispatch`** with the `upload_to_testflight` input set to
`true`; it archives, exports an App Store Connect IPA, and uploads via `altool`.
It depends on `build` succeeding first.

```sh
gh workflow run "iOS" --ref master -f upload_to_testflight=true
gh run list --workflow=ios.yml --limit 5
gh run watch <run-id> --exit-status
```

Equivalent UI path: **Actions → iOS → Run workflow → upload_to_testflight**.

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
- `scripts/prune_dev_certs.py` removes stale development certificates before
  archiving; it runs `continue-on-error` and may be skipped safely.
- Signing/provisioning often needs several iterations; treat a failed
  `testflight` job as expected on first runs and read the logs.
- A TestFlight public link requires an enrolled Apple Developer Program membership
  and an existing App Store Connect app record.

## CI gotchas

- `concurrency.group` is `ios-${{ github.ref }}` with `cancel-in-progress: true`.
  A manually triggered `workflow_dispatch` on `master` can cancel a push-triggered
  build on the same ref. If a push run shows `cancelled` after a few seconds,
  re-run it or trigger a dispatch.
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
- The scanner must never attempt to decrypt Apple's encrypted location payload;
  only decode public advertisement fields (status byte, public key, raw bytes).
- Scanning uses `CBCentralManagerScanOptionAllowDuplicatesKey` so RSSI and
  sighting counts update live.
