# PinFenster

A small, native macOS utility for keeping selected **original windows** in front using Accessibility APIs. Search your open windows, mark several, pause them, or release each one individually.

**Experimental:** this is automatic window raising, not a guaranteed system-wide always-on-top window level. Some apps ignore raising, take focus, or behave differently across Spaces and full-screen modes. The current version has passed ordering-policy tests; end-to-end pinning across third-party apps is not yet validated. Do not rely on it for critical workflows.

## Download

Get the `.dmg` from [Releases](https://github.com/manoelpanev/PinFenster/releases). The initial release supports Apple Silicon and Intel Macs running macOS 14 or newer.

The experimental download is **ad-hoc signed and not notarized**. Gatekeeper may block it. It is not a Developer ID distribution build. Review the source and Apple's guidance before deciding whether to run it; building locally is another option. Do not disable system protections.

## Use

1. Open the DMG and drag PinFenster into Applications.
2. Open the app and grant it Accessibility access in System Settings → Privacy & Security → Accessibility.
3. Find your app or window using search and choose **Anheften** (pin).
4. Choose **Lösen** to release a window, or **Alle lösen** to release all windows. The menu-bar icon also provides Release all and Quit.

The interface is currently German. Closing the management window leaves the menu-bar helper running. Quitting stops all raising; pins are not restored after restart. No screen recording permission is needed.

### Clicking the desktop

macOS can move every window aside when you click the wallpaper. PinFenster does not override that feature. In Desktop & Dock, set the wallpaper-click desktop-reveal option to **Only in Stage Manager**, with Stage Manager disabled, if you do not want that behavior. This setting affects all windows, not just pinned ones. PinFenster does not change it automatically.

## How it works

The helper checks roughly every 300 ms whether an ordinary overlapping window covers a selected window. It requests `AXRaise` only when needed. It does not synthesize input, activate the target application, capture pixels, or create mirror windows. It respects hidden/minimized windows and pauses raising while a mouse button is down or the management app is frontmost.

Two pinned windows do not repeatedly raise over each other. After three AX errors, the affected pin is released. A detected focus change to a target pauses raising. Delayed focus changes may escape this check, and a successful AX response does not prove that the target actually moved in front.

## Build and test

Requires Xcode with the macOS SDK and Swift compiler. No third-party dependencies.

```sh
bash scripts/test.sh
bash scripts/build.sh
```

Normal local builds require a valid code-signing identity. If exactly one identity is available it is selected and, after successful signing, its fingerprint is saved in `.signing-identity.local` (git-ignored) for later builds. Otherwise set `SIGNING_IDENTITY` to the certificate's SHA-1 fingerprint or save that fingerprint in `.signing-identity.local` yourself. Keep the same certificate, bundle identifier, and installation location for local updates. The build stops if signing cannot be completed; it never silently falls back to ad-hoc signing.

```sh
# Explicitly opt into an unnotarized experimental build:
bash scripts/build.sh --adhoc --universal
bash scripts/package.sh
```

Output: `build/PinFenster.app` and `dist/PinFenster-0.2.0-experimental-universal.dmg`.

## Signing

The bundle identifier is `local.mrpnv.pinfenster`, retained for compatibility with existing local installations. Stable certificate signing can preserve the designated requirement across rebuilds; it is not an unconditional guarantee that macOS will never ask for consent again. Switching to ad-hoc signing changes that identity and may invalidate prior grants.

An Apple Development or self-signed certificate is for local development. Public distribution without the usual unnotarized-app warnings requires **Developer ID Application signing and Apple notarization**. No signing certificates, private keys, or account credentials are included in this repository. CI deliberately builds an ad-hoc experimental artifact and cannot preserve your local developer signing identity.

References: [Apple Developer ID](https://developer.apple.com/developer-id/), [Apple notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Contributing

Fork this repository, create a branch in your fork, and open a pull request. Everyone can fork and propose changes; write access to this repository is limited to maintainers. See [CONTRIBUTING.md](CONTRIBUTING.md).

MIT licensed. No telemetry, network requests, or captured window content.
