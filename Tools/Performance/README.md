# Performance- en regressiecontrole

Voer vanuit de repository uit:

```sh
Tools/Performance/run_audits.sh
```

Dit compileert de echte Foundation-core en de tutorialdirector uit `Tutorial.swift` met de lokaal geïnstalleerde Swift-toolchain. De tijdelijke bestanden staan onder `/tmp` en worden opgeruimd. De controles lezen geen spelersvoortgang.

`CoreAudit.swift` controleert alle 99 levels, alle onderwerpen, alle modi, vier Supermix-varianten en drie seeds. Het controleert de berekeningen, het gekozen lesbereik, tafelvermenigvuldigers 0–12, precies één juist antwoord, zes verschillende waarden, vaste knopidentiteiten, uitsluitend vervanging van de gebruikte knop, de vaste oefenroute en directe herhalingen. Daarnaast worden gedeeltelijke stages en latere aanvulling getest.

`TutorialAudit.swift` controleert de productie-state-machine, inclusief handovers, hatches, verkeerde en goede quizkeuzes, drie tempovoorbeelden, pauzeren/hervatten en annuleren. De extractie neemt geen SwiftUI-weergave over; de volledige app-build en visuele controle dekken dat deel af.

`BaselineSample.swift` is de kleinere, identieke vergelijking van 8.100 rondes. Voer deze tegen een bewaarde oorspronkelijke checkout uit om een referentie te verkrijgen. De hoofdcontrole is strenger en hoort de dagelijkse regressiecontrole te zijn.

## Optionele diagnosevlaggen

Alle onderstaande hooks vallen onder `#if DEBUG` en staan niet in de gewone Release-build:

- `--performance-game`: opent een vaste tafel-3-les in volgorde, met tutorial, zonder de normale startupservices.
- `--performance-autoplay`: kiest via het echte speelveld de juiste antwoorden, doorloopt de quizzen, de vlucht en de levelreis. Het omzeilt de echte selectie- en hit-flow niet.
- `--performance-log`: schrijft `SPACE_PERF` en `SPACE_AUDIO` naar de console.

Gebruik voor tests altijd een afzonderlijke bundle-id, bijvoorbeeld `com.spacelion.performanceaudit`. De testgame kan voortgang schrijven binnen die eigen installatie. Vervang hiermee geen spelersinstallatie. Geen aankopen of pushregistratie zijn nodig voor de diagnose-route.

Voor compileroptimalisaties met behoud van uitsluitend de diagnosehooks kan een aparte testbuild worden gemaakt:

```sh
xcodebuild -project 'Space Lion.xcodeproj' -scheme 'Space Lion' \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/space-lion-performance-check \
  PRODUCT_BUNDLE_IDENTIFIER=com.spacelion.performanceaudit \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CODE_SIGNING_ALLOWED=NO build
```

Deze geoptimaliseerde diagnosebuild is geen distributiebuild. Controleer daarnaast de gewone Release-configuratie, zonder override van `SWIFT_ACTIVE_COMPILATION_CONDITIONS`.

## Interpretatie

`SPACE_PERF` meet de tijd tussen callbacks van een `CADisplayLink` op de main runloop. `p95_ms` is het 95e percentiel per meetvenster; `max_ms` omvat ook eenmalige pieken. Fases worden apart gemarkeerd. Dit meet de bereikbaarheid van de main runloop en is geen telling van gepresenteerde GPU-frames. ProMotion kan ook de callbackfrequentie veranderen.

`SPACE_AUDIO entrance_schedule_ms` meet vanaf het aanvragen van de startcue tot het plannen van de PCM-buffer. Het is geen meting van de hoorbare vertraging. De gerapporteerde I/O-buffer en outputlatency zijn eigenschappen van de huidige route.

CPU-profielen kunnen met Instruments/Time Profiler worden opgenomen. Exporteer de tabel `time-profile` en vat die samen met:

```sh
xcrun xctrace export --input /tmp/game.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  > /tmp/game-profile.xml
python3 Tools/Performance/profile_summary.py /tmp/game-profile.xml
```

De samenvatting bevat gewogen samples. Inclusieve categorieën overlappen; tel die niet bij elkaar op. Vergelijk bij voorkeur dezelfde buildconfiguratie, route, toestel, temperatuur en audio-uitvoer. Gebruik voor uiteindelijke FPS-claims ook Animation Hitches/Core Animation of Metal System Trace op hardware.

Zie `Reports/Performance/Analyse.md` voor de bevindingen en de bewaarde meetresultaten van 11 oktober 2026.
