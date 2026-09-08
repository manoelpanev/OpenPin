# Changelog

## 0.2.0 – Experimental

- Replaced screenshot overlays and synthetic input with native original-window raising.
- Added a searchable window list, per-window release, pinned view, pause and release-all controls.
- Added eight tests for window ordering and ambiguous/hidden-window handling.
- Added reproducible universal builds, explicit signing modes, and DMG packaging.
- Kept the existing bundle identifier for local signing continuity.

Known limitations: third-party app behavior is not yet end-to-end validated; this is not a guaranteed always-on-top implementation. Desktop reveal, Spaces, fullscreen and focus behavior remain platform/app dependent. Initial public binaries are ad-hoc signed and not notarized.
