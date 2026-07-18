# Local Strike Godot

Ein eigenstaendiger taktischer 5v5-Shooter fuer Godot 4.7. Das Spiel enthaelt Solo-Bots, LAN-Grundfunktionen, Defusal und Team Deathmatch. Es verwendet keine Counter-Strike-Assets oder geschuetzten Namen.

![Local Strike auf der Karte Old Quarter](docs/old-quarter.png)

## Start

- Godot 4.7 installieren und das Projekt importieren. Alternativ die portablen Windows-Dateien in `engine/` ablegen.
- `START_GAME.cmd` startet Forward+ mit Vulkan und wechselt bei einem Startfehler automatisch zu OpenGL. Es findet Godot im Projekt oder ueber `PATH`.
- `START_GAME_COMPATIBILITY.cmd` erzwingt den sparsamen OpenGL-Modus.
- `OPEN_EDITOR.cmd` oeffnet das Projekt im Godot-Editor.
- `RUN_TESTS.cmd` prueft 17 Ausruestungsobjekte, Ballistik, fuenf Karten, 5v5-Spawns, Sandbox-Werkzeuge, Movement, Interaktionen, Effektlimits, Deathmatch und LAN-Sockets.

Der portable Editor selbst ist wegen GitHubs 100-MB-Dateigrenze nicht Teil des Repositories. Details stehen in `engine/README.md`.

## Spielmodi

- Defusal: Best of 7, Seitenwechsel nach drei Runden, 12 Sekunden Kaufphase, 105 Sekunden Rundenzeit und 35 Sekunden Charge-Timer.
- Team Deathmatch: acht Minuten oder 40 Kills, freie Ausruestung und Respawns nach drei Sekunden.
- Sandbox: lokaler Endlosmodus mit freier Ausruestung, unendlicher Munition, optionalem God Mode und frei platzierbaren Bots, Physikobjekten, Waffen, Explosionen und Brawl-Waves.
- Solo fuellt beide Teams bis 5v5 mit Bots auf.
- LAN verwendet ENet auf UDP-Port `27888`; lokale Server werden ueber UDP-Port `27889` gefunden. Direkte IP ist ebenfalls moeglich.

## Ausstattung

- 14 Waffen inklusive Vanguard Revolver, Whisper SMG, Sentinel Carbine, Hammer Battle Rifle, Cyclone Auto-Shotgun und Bulwark LMG
- Frag-, Rauch-, Flash- und Brandgranaten mit Sprungphysik, Sichtlinien und Flaechenschaden
- Fuenf Karten: Harbor Yard, Train Depot, Solar Lab, Old Quarter und Frostline Station
- Kopf-, Torso- und Gliedmassen-Trefferzonen
- Deterministische Rueckstossmuster, ADS, Feuerwahl, Schadensabfall, bis zu drei Durchdringungen und ein Abpraller
- Bewegliche Kisten und Frachtobjekte, zerstoerbare Deckung, Explosionsimpulse, Waffen-Drops und kosmetische Ragdolls
- Bodenreibung, Eisflaechen, Luftkontrolle, Fallschaden, sicheres Ducken und automatisches Uebersteigen niedriger Deckung
- Humanoide Scout-, Assault- und Heavy-Bots mit Sicht, Geraeuschsuche, Teamzielen und drei Schwierigkeitsstufen
- Schiebetueren mit Blockierschutz, zerbrechliches Glas, ausschaltbare Lampen und explodierende Brennstoffbehaelter

## Sandbox

![Sandbox-Werkzeuge auf Old Quarter](docs/sandbox-720p.png)

Sandbox wird im Hauptmenue als dritter Modus gestartet und laeuft bewusst lokal. Das Werkzeugpanel und die freie Ausruestung werden mit `B` geoeffnet. Objekte und Figuren erscheinen am anvisierten Punkt; `RESET WORLD` stellt Karte, Bots und Physikobjekte vollstaendig wieder her.

## Grafik und Audio

- Forward+ mit 4x MSAA, SSAO, SSIL, SSR, Glow, volumetrischem Nebel und 4096er Schatten im Profil Hoch
- Qualitaetsprofile Hoch, Mittel und Niedrig
- Korrekt verwendete CC0-ARM/ORM-PBR-Materialien fuer Beton und Metall sowie prozedurale Normaldetails
- Eigene Geometrie fuer Container, Pfuetzen, Flutlichter, Hafenkran, Gleise, Signale, Zuege, Solarpanels und Laborkern
- Humanoide Figuren mit animierten Armen und Beinen sowie unterschiedliche Viewmodels fuer alle Waffenkategorien
- Oberflaechenspezifische Funken, Staub, Glassplitter, Blutnebel, Tracer, Decals, Explosionen und dichter Rauch
- Raeumliche Kenney-CC0-Schritt-, Metall-, Glas- und Einschlagsounds; Schuesse und Explosionen besitzen einen prozeduralen Fallback

Die CC0-Herkunft ist in `ASSET_LICENSES.md` dokumentiert.

## Leistung

Der aktuelle Physik-Build erreichte auf einer RTX 3070 bei 1920x1080, Profil Hoch und zehn aktiven Figuren in einer 50-Sekunden-Forward+-Messung durchschnittlich 144 FPS; keines der 200 Samples lag unter 55 FPS. Das maschinenlesbare Ergebnis liegt in `docs/benchmark-physics.json`, der Runner kann mit einer beliebigen Dauer erneut gestartet werden.

## Steuerung

- `WASD`: bewegen
- Maus: zielen
- Linksklick: schiessen oder Granate werfen
- `Leertaste`: springen
- `Strg`: ducken
- `Shift`: sprinten
- `R`: nachladen
- Rechtsklick: ADS / Zielfernrohr
- `V`: Feuerart bei Sentinel und Hammer wechseln
- `G`: nahe Waffe aufnehmen oder aktuelle Schusswaffe fallenlassen
- `1`: Primaerwaffe
- `2`: Sidearm
- `3`: Messer
- `4`: Granate
- `E`: Charge setzen, entschaerfen oder nahe Tuer bedienen
- `B`: Ausruestungsmenue
- `F5`: Sandbox-Gegner platzieren
- `F6`: Sandbox-Verbuendeten platzieren
- `F7`: Sandbox-Holzkiste platzieren
- `F8`: Sandbox-Explosion am Zielpunkt
- `F9`: Sandbox-Zeitlupe
- `F10`: Sandbox-Spawns entfernen
- `M`: im Sandbox-Modus zur naechsten Karte wechseln
- `Tab`: Scoreboard
- `Escape` oder `P`: Pause
- `F2`: Match neu starten

## LAN

1. Auf einem Rechner im Hauptmenue `HOST LAN - 5v5` waehlen.
2. Auf weiteren Rechnern `REFRESH LAN` verwenden und den Server doppelklicken.
3. Falls Broadcast durch das Netzwerk blockiert wird, die lokale IPv4-Adresse direkt eingeben.
4. Bei einer Windows-Firewallabfrage den privaten Netzwerken Zugriff auf UDP `27888` und `27889` erlauben.
