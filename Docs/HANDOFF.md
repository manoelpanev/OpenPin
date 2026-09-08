# OpenPin — Handoff

Für die nächste Session (Claude oder Codex). Liest sich in unter 5 Minuten.

## Was OpenPin ist

macOS-Menüleisten-App: pinnt Fenster als schwebendes App-Icon, das per Klick das
Originalfenster an die Icon-Position holt, und per Klick auf eine kleine Ecke am
Fenster (oder ⌃⌥P) wieder zurück ins Icon schickt. Optionale Live-Vorschau via
ScreenCaptureKit. Bundle-ID `local.mrpnv.pinfenster`, App-Name `OpenPin`.

Repo: https://github.com/manoelpanev/OpenPin (umbenannt von PinFenster).

## Aktueller Stand (Stand: 2026-09-08, Commit siehe `git log -1`)

- **Kernfunktion (pin → Icon → Fenster raus/rein):** fertig, nativ getestet,
  siehe `TEST-RESULTS.md`.
- **Neue Funktion: Fensterübersicht** (`Sources/Switcher.swift`), gerade gebaut:
  dunkles Overlay mit Live-Thumbnails aller offenen Fenster oben, App-Icon-Grid
  darunter. Aufruf über Menü **Fenster → Fensterübersicht anzeigen** funktioniert
  zuverlässig. **Globales Tastenkürzel ⌥Leertaste ist noch kaputt** — der
  `NSEvent.addGlobalMonitorForEvents`-Handler sieht den Tastendruck nachweislich
  (per Logging bestätigt: `code=49 flags=524320`, also Space+Option korrekt
  erkannt, `toggle()` wird aufgerufen), aber das Panel erscheint trotzdem nicht
  sichtbar auf dem Bildschirm. Ein erster Fix (Aktivierungsreihenfolge in
  `SwitcherController.show()`: erst `NSApp.activate`, dann
  `panel.makeKeyAndOrderFront`) hat das Problem NICHT gelöst. Nächster
  Verdacht: `windowDidResignKey` auf dem Panel-Delegate feuert eventuell durch
  das `NSApp.activate` selbst noch einmal indirekt, oder das Panel bekommt nie
  wirklich `orderFront`, weil `level = .popUpMenu` mit einer anderen
  gerade-aktiven App kollidiert. Bewusst noch nicht tiefer verfolgt, um
  Zeitbudget zu schonen — der Menü-Weg ist der zuverlässige Fallback bis das
  gelöst ist.

## Offene Aufgabe, NUR NOTIERT, NICHT UMSETZEN bis explizit beauftragt

**Idee vom Nutzer:** Das Hauptfenster von OpenPin (`PinInterface` in
`Sources/OpenPin.swift`) soll optisch dem neuen Switcher-Overlay-Stil ähneln
(siehe Screenshot-Referenz „InfyniDock"-artiges Overlay: dunkle Karte,
Live-Thumbnails oben, App-Grid darunter). Zusätzlich: das Hauptfenster selbst
soll fixierbar sein — vermutlich analog zum bestehenden Pin-Mechanismus, aber
für das Verwaltungsfenster selbst (always-on-top statt normales Fenster).

**Wichtig:** Der Nutzer hat ausdrücklich gesagt, das nur aufzuschreiben, nicht
zu bauen. Erst umsetzen, wenn im Gespräch explizit dazu aufgefordert.

## Bekannte, aber nicht OpenPin-eigene Baustellen

- **InfyniDock** (Drittanbieter-Dock-App, `www.infyniclick.com.dock`,
  `/Applications/InfyniDock.app`) läuft parallel für offene-Fenster-Anzeige.
  Deren „Finder im Dock anzeigen"-Schalter (`showFinderInDock`) ist aktiviert,
  zeigt Finder-Fenster aber nachweislich trotzdem nicht in der Leiste — reproduziert
  bestätigter Bug in der Fremd-App, keine OpenPin-Baustelle. Nicht weiter verfolgen,
  außer der Nutzer bittet erneut darum.
- Natives macOS-Dock hatte einmal das Finder-Icon komplett verloren
  (`persistent-apps` in `com.apple.dock` ohne Finder-Eintrag). Behoben durch
  manuellen Re-Add + `killall Dock`. Ursache unklar, evtl. Zusammenhang mit
  InfyniDocks „Finder im Dock anzeigen aus"-Test von vorhin. Falls es wieder
  auftritt: `defaults read com.apple.dock persistent-apps | grep -c finder`
  prüfen.

## Bauen & Testen

```sh
bash scripts/test.sh    # 8 capture-source + 4 bubble-geometry Tests
bash scripts/build.sh   # signierter Debug-Build nach build/OpenPin.app
```

Beide liefen zuletzt grün, inklusive der neuen Switcher.swift-Datei.

## Sicherheitshinweis für die nächste Session

Beim Testen ist mehrfach unbeabsichtigt ein 1Password-Fenster mit Klartext-
Zugangsdaten des Nutzers in Screenshots gelandet (Nebeneffekt von
Fenster-Aktivierungs-Tests, nicht von OpenPin selbst verursacht). Werte wurden
nirgends verwendet oder gespeichert. Bei weiteren nativen UI-Tests: möglichst
vermeiden, fremde Apps per Klick/Aktivierung in den Vordergrund zu holen, wenn
nicht nötig — lieber gezielt nur OpenPin selbst ansteuern.
