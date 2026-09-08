# OpenPin

OpenPin keeps a pinned app window one click away as a **floating app icon**. Each pinned window becomes a small levitating icon (Telegram, Spotify, WhatsApp, …) that stays above ordinary windows. Click the icon and the **original window comes out of it**: it is moved to the icon's position on the icon's screen and brought to the front. Switch to another app and the icon floats back.

A **live view** of the window is still available: right-click the icon and choose *Live-Ansicht anzeigen*, or use **Fenster → Live-Ansichten anzeigen** (⌘L). The live view grows out of the icon's corner, and *Als Symbol* shrinks it back into the icon. The live view uses a floating native NSPanel and ScreenCaptureKit; it does not change the original application's window level.

## Use

1. Open `build/OpenPin.app` and allow Accessibility access for the window list and for moving/raising originals.
2. Search for an app and choose **Anheften**. macOS may ask for screen recording access, which the live view needs.
3. The app icon appears floating at the top right and gently hovers. Drag it anywhere, on any display.
4. **Click the icon**: the original window appears at the icon's position and gets focus. When you switch apps, the icon returns.
5. **Right-click the icon** for *Original öffnen*, *Live-Ansicht anzeigen* and *Lösen*. In the live view, *Original öffnen ↗* hands off to the original and *Als Symbol ⌄* returns to the icon.
6. **Lösen**, closing the live view, or **Alle lösen** ends a pin. Closing the management window leaves the icons running; quitting OpenPin stops them.

**Alle pausieren** hides the icons and views; capture remains active until released. Reduced-motion settings disable the hover, pop and grow animations.

Images remain in memory on your Mac: no files are recorded, no audio is captured, and nothing is uploaded. Screen recording permission is required even though OpenPin does not save recordings. The capture filter selects only the chosen window.

## Limits

Protected content, minimized windows, system dialogs and some fullscreen/Space combinations may behave differently. Moving the original to the icon depends on the app honoring accessibility position changes; a window larger than the icon's screen is aligned to that screen's edge. The live view is not directly interactive: clicks open the original rather than forwarding input into a video. Pins are not restored after quitting.

See [TEST-RESULTS.md](TEST-RESULTS.md) for native test evidence and remaining untested cases. Geometry tests alone do not prove a working live stream or correct system window ordering.

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

Outputs are `build/OpenPin.app` and `dist/OpenPin-0.4.0-experimental-universal.dmg` for the universal packaging command. The current local update has not been published. Existing [GitHub releases](https://github.com/manoelpanev/PinFenster/releases) use the former PinFenster name and behavior.

The bundle identifier remains `local.mrpnv.pinfenster` for local permission continuity. Local Apple Development signing is not Developer ID notarization. Ad-hoc rebuilds may require granting permissions again.

## Implementation

Accessibility identifies the source window by process and geometry. Each pin owns two nonactivating floating panels: a transparent 104-point icon bubble and the live-view panel. The bubble rasterizes the app icon at the display's pixel density and animates a Core Animation hover loop; a spring pop marks its return. Handoff moves the original with the accessibility position attribute, activates the app through Launch Services (a direct activation request is refused when the system does not credit OpenPin with recent user interaction), and raises the window with AXRaise. A short grace period keeps the icon hidden until the target app is in front.

ScreenCaptureKit streams the window into an AVSampleBufferDisplayLayer at up to 30 fps with a maximum capture dimension of 1600 pixels. The live view is shown only on request; it grows out of, and shrinks back into, the bubble's top-right corner and stays inside the bubble's screen. All capture objects are stopped on release.

A read-only diagnostic command prints WindowServer metadata:
`build/OpenPin.app/Contents/MacOS/OpenPin --window-order`.
It must run in a session with access to WindowServer. Sandbox-denied access can produce an empty list.

References: [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos), [Apple window collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces), [Apple cooperative activation](https://developer.apple.com/documentation/appkit/nsrunningapplication/activate(from:options:)), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

MIT licensed. See [CONTRIBUTING.md](CONTRIBUTING.md).
