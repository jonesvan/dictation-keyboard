# Dictation Keyboard

An iOS custom keyboard that turns speech into text using Apple's built-in
speech recognition stack (the `Speech` framework). It works in any app that
accepts text input.

> **Not Siri's private model.** Apple does not expose the Siri dictation model to
> third-party apps. This project uses the public `Speech` framework
> (`SFSpeechRecognizer`), which powers system dictation. On iOS 26+ you can
> migrate the engine to `SpeechAnalyzer` / `SpeechTranscriber`; the keyboard
> extension code does not need to change.

## Status

This repository contains source and an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec. It has **not been compiled or signed** here (the authoring environment is
Linux and has no Xcode). You must build it on a Mac.

## Layout

```
DictationKeyboardApp/   Containing app: permissions + setup instructions
KeyboardExtension/      The keyboard (UIInputViewController)
Shared/                 Speech engine shared by both targets
project.yml             XcodeGen project spec
```

## Build

Requires macOS with Xcode 15+ and the iOS 17+ SDK.

```sh
brew install xcodegen
xcodegen generate
open DictationKeyboard.xcodeproj
```

In Xcode:

1. Select the `DictationKeyboard` project and set your **Team** on both targets.
2. Change the bundle identifiers from `com.example.*` to your own.
3. Run on a **physical device** (keyboard extensions and the microphone do not
   work reliably in the Simulator).

## Continuous integration

`.github/workflows/ios.yml` builds the app on a GitHub-hosted macOS runner on
every push and pull request:

- installs XcodeGen, generates the project, and runs `xcodebuild` for the iOS
  Simulator with code signing disabled — a pure compile check.

To also archive and upload to TestFlight, add these repository secrets
(**Settings → Secrets and variables → Actions**) and run the workflow manually
with `upload_to_testflight` enabled:

| Secret | Description |
| --- | --- |
| `ASC_KEY_ID` | App Store Connect API key ID |
| `ASC_ISSUER_ID` | App Store Connect API issuer ID |
| `ASC_KEY_CONTENT` | The full contents of the `.p8` API key file (the `-----BEGIN PRIVATE KEY-----` text) |
| `APPLE_TEAM_ID` | Your 10-character Apple Developer Team ID |

The upload job is best-effort and untested; signing/provisioning usually needs a
few iterations.

## TestFlight

A TestFlight link cannot be generated without an Apple Developer Program
membership and an App Store Connect app record. To ship a beta:

1. Enroll in the Apple Developer Program.
2. Create an app in App Store Connect with bundle ID `com.yourco.DictationKeyboard`.
3. Either follow the CI steps above, or in Xcode select the app target →
   **Product → Archive**, then in the Organizer choose **Distribute App → App
   Store Connect → Upload**.
4. In App Store Connect → TestFlight, wait for processing, add testers, and
   Apple will issue the public link for that build.

## Enabling the keyboard

Settings → General → Keyboard → Keyboards → Add New Keyboard → Dictation, then
enable **Allow Full Access** (required for microphone access in a keyboard
extension).

## Known limitations

- Keyboard extensions have restricted audio access; microphone permission must be
  granted and **Allow Full Access** enabled.
- `requiresOnDeviceRecognition` needs the on-device model downloaded for the
  selected locale, otherwise recognition fails — use the on-device toggle in the
  app only when the model is available.
- Partial results are inserted and then corrected; very fast typing while
  dictating can interleave text.

## License

MIT
