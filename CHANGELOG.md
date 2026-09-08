# Changelog

## 0.3.0 – OpenPin live views, local build

- Renamed the source, executable, app bundle, interface and build artifacts to OpenPin. Retained the bundle identifier for existing permissions.
- Replaced unsuccessful original-window raising with ScreenCaptureKit live views in nonactivating floating panels.
- Each panel shows its source app's icon and name, plus an explicit Original öffnen control. Clicking the image also opens the original; switching apps restores the view.
- Added capture cleanup, startup failure reporting and a Fenster menu command to show views.
- Kept a read-only window-order diagnostic and geometry regression tests. No audio, saved recordings or network transfer. Additional screen recording permission is required.
- Local build only; not published or notarized. The original-window approach's failed Spotify/Chrome test is preserved in TEST-RESULTS.md.

## 0.2.0 – Experimental

- Replaced screenshot overlays and synthetic input with native original-window raising.
- Added a searchable window list, per-window release, pinned view, pause and release-all controls.
- Added eight tests for window ordering and ambiguous/hidden-window handling.
- Added reproducible universal builds, explicit signing modes, and DMG packaging.
- Kept the existing bundle identifier for local signing continuity.

Known limitations: third-party app behavior is not yet end-to-end validated; this is not a guaranteed always-on-top implementation. Desktop reveal, Spaces, fullscreen and focus behavior remain platform/app dependent. Initial public binaries are ad-hoc signed and not notarized.
