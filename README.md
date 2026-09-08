# OpenPin

OpenPin keeps a **live view of a selected window** above ordinary app windows. Each view shows the source application's icon and name. Click the image or **Original öffnen** to use the real window; when you switch to another app, the live view returns.

The live view uses a floating native NSPanel and ScreenCaptureKit. It does not change the original application's window level. The previous AXRaise approach failed a native Spotify/Chrome test and has been removed from the running engine.

## Use

1. Open `build/OpenPin.app` and allow Accessibility access for the window list and opening originals.
2. Search for an app and choose **Anheften**. macOS may ask for screen recording access for the live view.
3. Drag the floating view by its title bar or resize it at its edges. Its header contains the application's icon.
4. Click the image or **Original öffnen** to operate the original. Switch apps to restore the floating view.
5. Choose **Lösen**, close the floating view, or use **Alle lösen**. Closing the management window leaves the views running; quitting OpenPin stops them.

**Fenster → Live-Ansichten anzeigen** (⌘L) brings your views back explicitly. **Alle pausieren** hides the views; capture remains active until released.

Images remain in memory on your Mac: no files are recorded, no audio is captured, and nothing is uploaded. Screen recording permission is required even though OpenPin does not save recordings. The capture filter selects only the chosen window.

## Limits

Protected content, minimized windows, system dialogs and some fullscreen/Space combinations may behave differently. The live view is not directly interactive: clicks open the original rather than forwarding input into a video. Stopping capture or closing a source may require pinning it again. Pins are not restored after quitting.

See [TEST-RESULTS.md](TEST-RESULTS.md) for native test evidence and remaining untested cases. Geometry-policy tests alone do not prove a working live stream or correct system window ordering.

## Build

Requires the macOS SDK and Swift compiler. No third-party dependencies. macOS 14 or newer.

```sh
bash scripts/test.sh
bash scripts/build.sh
```

The build requires a valid signing identity. Set `SIGNING_IDENTITY` if more than one is available. When exactly one identity is found, the script uses it and saves its fingerprint in the git-ignored `.signing-identity.local`. Reuse the same identity and bundle identifier for local updates.

```sh
# Explicit experimental distribution build, not notarized:
bash scripts/build.sh --adhoc --universal
bash scripts/package.sh
```

Outputs are `build/OpenPin.app` and `dist/OpenPin-0.3.0-experimental-universal.dmg` for the universal packaging command. The current local update has not been published. Existing [GitHub releases](https://github.com/manoelpanev/PinFenster/releases) use the former PinFenster name and behavior.

The bundle identifier remains `local.mrpnv.pinfenster` for local permission continuity. Local Apple Development signing is not Developer ID notarization. Ad-hoc rebuilds may require granting permissions again.

## Implementation

Accessibility identifies the source window by process and geometry. ScreenCaptureKit streams that window into an AVSampleBufferDisplayLayer at up to 30 fps, with a maximum capture dimension of 1600 pixels. A nonactivating floating NSPanel keeps it above ordinary windows without repeatedly activating the source app. User-requested handoff activates the source; the next app activation restores the view. All capture objects are stopped on release.

A read-only diagnostic command prints WindowServer metadata:
`build/OpenPin.app/Contents/MacOS/OpenPin --window-order`.
It must run in a session with access to WindowServer. Sandbox-denied access can produce an empty list.

References: [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [Apple window collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

MIT licensed. See [CONTRIBUTING.md](CONTRIBUTING.md).
