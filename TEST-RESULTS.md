# OpenPin native tests — 2026-09-08

## 0.4.0 floating icon: passed for Spotify

Driven through the accessibility tree and WindowServer metadata on a three-display setup (built-in 1512×982 main, two 1920×1080 externals).

| Check | Observed result |
| --- | --- |
| Icon bubble | Pinning Spotify created a 104×104 layer-3 window „Spotify · OpenPin Symbol“ with the Spotify icon, shadow and green live dot; screenshot showed it crisp next to Launchpad icons. |
| Click opens original | An accessibility press on the bubble hid it; after 2 s Spotify was the frontmost process. With the earlier direct `activate()` call this failed (`activate=0`), which is why handoff now goes through Launch Services. |
| Window placed at the icon | Spotify's 1512×893 window moved from the left display (−1601, 154) to the icon's display at (0, 39): the icon's corner, clamped to the screen edge because the window is wider than the space left of the icon. |
| Icon returns | Activating Finder brought the bubble back at the same position. |
| Live view grows from the icon | ⌘L opened the 520×352 panel sharing the bubble's top-right corner (2900, −56 vs. bubble 3324, −56). |
| Collapse | „Als Symbol“ removed the panel and placed the bubble back at (3324, −56). |
| Return pill | While Spotify was out, a 58×32 layer-3 window „Spotify · OpenPin Zurück“ sat at (1448, 44), the top-right corner of Spotify's window at (0, 39, 1512×893). |
| Back into the icon | Pressing the pill hid Spotify (process no longer visible), Finder became frontmost and the bubble reappeared at its previous position (900, 500). Clicking the bubble again unhid and raised Spotify. |
| Tests and build | 8 capture-source and 4 bubble-geometry tests pass; signed local build with the new AppIcon.icns succeeded. |

Not tested this round: real mouse drag of the bubble, right-click menu, the ⌃⌥P shortcut, multiple simultaneous bubbles, the minimize path for multi-window apps, reduced-motion path, and apps that ignore accessibility position changes.


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
