# OpenPin native test — 2026-09-08

## Live-view result: passed for Spotify

The user approved a floating live view with the source app's icon and click-to-original handoff. OpenPin was built with the existing Apple Development identity and unchanged bundle identifier. Accessibility and ScreenCaptureKit access were available; the first stream started without another permission grant.

| Check | Observed result |
| --- | --- |
| Live picture | Spotify contents rendered in the floating panel. |
| Source icon | Screenshot and accessibility tree showed the Spotify icon beside the app name. |
| Above ordinary windows | WindowServer reported OpenPin panel 31396 on layer 3, before the overlapping ChatGPT window 28683 on layer 0. The panel was at (2888, -18), 520×383; the other window at (1520, -68), 1920×994. |
| Click to original | Clicking Original öffnen hid the panel and raised Spotify's original window ahead of Chrome. Returning to another app restored the floating view on layer 3. |
| Live updates and direct original input | Typing a temporary test string into Spotify's search field changed the original UI and appeared in the live view screenshot. The test string was cleared afterward. |
| Release | Closing the floating panel removed it and changed the management count to 0 with Anheften available again. |
| Build and identity checks | Signed local build succeeded; eight capture-source identity tests passed, including process isolation, duplicate rejection, accessory windows and negative monitor coordinates. |

No audio playback control was intentionally used. No screenshot or recording files were saved. Source window content was processed locally and viewed through the existing computer-use surface.

## Practical limits

Fullscreen, multiple simultaneous pins, source minimization, screen disconnection, permission revocation and desktop-click reveal are not fully tested. An F11 attempt did not establish that desktop reveal was triggered, so it is not counted as a passing desktop-reveal test.

The nonactivating panel uses floating level 3 and canJoinAllSpaces/fullScreenAuxiliary/stationary behavior. The practical claim is that the live view stayed above ordinary overlapping windows in this test. It is not a claim that the original window gained an always-on-top level.

Pausing hides views but does not stop capture; releasing stops capture. The stream requests no audio and does not write captured frames to disk. Source selection fails on ambiguous process/geometry matches rather than guessing.

## Previous original-window approach: failed

Before the approved live-view change, Chrome window 30984 remained ahead of Spotify window 27729 despite accepted AXRaise calls. OpenPin correctly reported ineffective raising and released the pin. Removing a management-app pause and excluding a 66×20 same-app accessory did not resolve that failure. That raising loop is no longer part of the running engine.

Desktop & Dock showed wallpaper-click reveal set to Always and Stage Manager off. No global setting was changed.

## Sources

- [Apple AXRaise](https://developer.apple.com/documentation/applicationservices/kaxraiseaction): raising is limited by the containing application's circumstances.
- [Apple ScreenCaptureKit sample](https://developer.apple.com/documentation/screencapturekit/capturing-screen-content-in-macos): window-specific capture and stream rendering.
- [Topsy implementation record](https://github.com/andhikapraa/topsy/blob/main/docs/dev/HANDOFF.md): a separate project's investigation of foreign-window level limitations and live views; not evidence for OpenPin's own tests.

## Reproduce

1. Open the signed build, search for Spotify and choose Anheften.
2. Use Fenster → Live-Ansichten anzeigen (⌘L), inspect the icon, and switch to another ordinary app.
3. Click Original öffnen, type in Spotify's search field, switch apps and inspect the updated view.
4. Close the floating view and verify that the pin count becomes zero.

The read-only `--window-order` command reports process names, layers, IDs and geometry. Run it from a session with WindowServer access; a sandbox may return an empty list.
