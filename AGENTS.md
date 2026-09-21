# AGENTS.md

Guidance for agents working in this repository.

## What this is

An iOS custom keyboard (`UIInputViewController`) that dictates speech using
Apple's `Speech` framework. Layout:

```
DictationKeyboardApp/   Containing app (permissions + setup UI)
KeyboardExtension/      The keyboard target
Shared/                 Speech engine shared by both targets
project.yml             XcodeGen spec (source of truth, do NOT hand-edit an .xcodeproj)
.github/workflows/ios.yml   CI: build + optional TestFlight deploy
```

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
behavior.

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

- Bundle IDs are `com.jonesvan.DictationKeyboard` and
  `com.jonesvan.DictationKeyboard.Keyboard` (set in `project.yml`).
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
- Keep `Shared/DictationEngine.swift` free of UIKit so both targets can use it.
- Audio/speech calls that can fail must surface a diagnostic via the engine's
  `onLog`/`onError` callbacks; the keyboard renders them in its on-screen log.
- CoreAudio error `2003329396` (`'what'`, `AUIOClient_StartIO failed`) is a
  transient I/O-start race; retry with backoff rather than switching categories.
