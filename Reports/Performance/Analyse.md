# Space Lion — performanceanalyse en uitgevoerde verbeteringen

**Datum: 11 oktober 2026.** Onderzocht: levelstart, tutorial, vraagkwaliteit, renderwerk, animatiecadans, pauzeren en herstarten. De referentie is de werkmap zoals die bij aanvang van dit onderzoek bestond. Daarin stonden al wijzigingen aan audio, tutorial, vormgeving en vragen. Die zijn behouden; vergelijken met alleen Git HEAD zou een andere uitgangssituatie geven.

Er zijn concrete fouten gevonden en hersteld in de timing en de vraagplanning. Er is ook terugkerend tekenwerk verminderd. De meting op een fysieke iPhone wijst op minder grote uitschieters tijdens het spelen. Er zijn nog incidentele pieken en er is geen bewijs voor volledig constante gepresenteerde 60 FPS.

## 1. Bevindingen en acties

| Prioriteit | Bevinding | Uitgevoerd |
| --- | --- | --- |
| Hoog | Een snelle koude levelstart kon de zichtbare entree beginnen terwijl de effectenengine nog niet gereed was. | De entree wacht kort op audiogereedheid; normale warme starts lopen meteen door. Een mislukte audio-uitvoer heeft een fail-open timeout van 0,8 seconde. Wachten kan bij vertrek worden geannuleerd. |
| Hoog | Muziekvoorbereiding en effectvoorbereiding deelden één wachtrij. Warme effecten raakten opnieuw voorbereiding, sessieactivatie en muziekaansturing aan. | Muziek en effecten hebben eigen wachtrijen. Het warme effectpad plant uitsluitend de bestaande PCM-buffer. Bij alleen muziek wordt de effectencatalogus niet geladen. |
| Hoog | De planner herschikte de vaste oefenroute om zes verschillende toekomstige antwoorden te krijgen. Bij kleine antwoordpools ontstonden herhalingen of noodvragen buiten de bedoelde route. | De echte vragen worden eerst in de gekozen route gepland. Het bord ondersteunt terugkerende antwoordwaarden en vervangt uitsluitend de gebruikte knop. |
| Hoog | Tutorialvertragingen konden tijdens pauze of achtergronding doorlopen. | Overgangen en het sluiten van de luiken bewaren hun resterende actieve tijd en hervatten daarna. Annulering voorkomt oude callbacks in een nieuwe sessie. |
| Hoog | Het renderpad bevatte veel losse tussenlagen voor bewegende beelden en eenvoudige uitsneden. | Tussenlagen per asteroïde en per energierail zijn vervangen door gekopieerde tekencontexten. Uitsneden blijven lokaal; bestaande licht- en diepte-effecten blijven aanwezig. |
| Middel | De vaste cockpit kon opnieuw worden opgebouwd door feedback- en modelwijzigingen. | Een aparte vergelijkbare statische laag reageert op geometrie, personage, bestemming en beschikbaar artwork. Feedback en bewegende decoratie hebben eigen lagen. |
| Middel | De snelle levelreis gebruikte dezelfde 30 Hz-cadans als de langzame karakterpose. | De reis heeft een eigen nominale 60 Hz-cadans, of 30 Hz bij energiebesparing/hoge thermische belasting. |
| Middel | De gewone achtergrond bleef onder de reis tekenen terwijl die niet zichtbaar was. | Verborgen ruimtebeelden worden tijdens de reis overgeslagen. |
| Middel | Beelden bleven onbeperkt in de voorbereidingscache staan; asteroïden waren groter dan voor hun weergave nodig. | Een `NSCache` met een budget van 48 MiB en 40 beelden vervangt de onbeperkte opslag. Asteroïden worden vooraf naar maximaal 512 pixels geschaald. |
| Middel | Pauzeren rondde resterende tijd telkens omhoog af. Een herstart begon de klok al tijdens de entree. | Pauze bewaart fracties van seconden. Een herstart bereidt het spel voor en opent klok, invoer en eerste vraag na het landen. |
| Middel | In gemengde percentages stond het huidige percentage aan het verkeerde einde van de gewogen lijst. | De lijst volgt nu de lesvolgorde, met het huidige percentage op de voorkeurspositie. |
| Laag | Cycli verschoven arrays; gewichten en geschikte procentgetallen werden herhaaldelijk berekend. | Cycli gebruiken een cursor; brongewichten en decimale kandidaatgetallen worden hergebruikt. |

## 2. Metingen en hun betekenis

Er zijn afzonderlijke testinstallaties gebruikt, met eigen bundle-id's. De normale game-installaties zijn niet vervangen. Geautomatiseerde antwoorden lopen via de echte selectie, vlucht, contact- en afrondingslogica. De route bevat de tutorial, twintig juiste antwoorden, een levelreis en het resultaat. Er zijn zowel Debug-builds als builds met Release-compileroptimalisaties gebruikt.

De frameprobe meet de tijd tussen `CADisplayLink`-callbacks op de main runloop. Het 95e percentiel beschrijft de langzaamste 5% binnen een venster. Dit is **geen GPU-telling van gepresenteerde frames**. ProMotion, achtergrondprocessen en de simulator kunnen de callbackcadans beïnvloeden. Een venster van 24 ms betekent dus niet dat het spel continu op 42 FPS draait.

### Fysieke iPhone 17 Pro, iOS 26.6.1

Beide versies zijn met compileroptimalisaties gebouwd en hebben dezelfde automatische route doorlopen. Het betreft één volledige opname per versie; dit is een praktische controle, geen statistisch benchmarkonderzoek.

| Maat | Oorspronkelijke versie | Aangepaste versie |
| --- | --- | --- |
| p95 in de eerste zes vensters van de speelsessie | 32,51 / 38,97 / 25,04 / 28,78 / 22,28 / 32,59 ms | Actieve speelfases: 22,88–24,94 ms |
| Grootste gemeten callbackpauze bij koude aanvang | 455,60 ms in het eerste gecombineerde venster | 183,37 ms in de apart gemarkeerde intro |
| Grootste callbackpauze binnen actieve speelfases | Tot 51,80 ms in de volgende volledige vensters | Tot 37,53 ms |
| Aangepaste levelreis | Referentievensters mengen reis en spelen | p95 16,72 ms; maximum 25,88 ms |
| Planning van de startcue | Geen aparte timinglog in deze referentie | 0,01 ms; I/O-buffer 5 ms; gerapporteerde outputlatency 12,37 ms |

De resultaten wijzen op een gelijkmatiger bereikbaarheid van de main runloop, vooral doordat grote uitschieters minder voorkomen. De oude probe had geen fasemarkeringen: de vensters zijn daarom niet exact één-op-één te vergelijken. Een percentage FPS-winst zou hiermee onvoldoende onderbouwd zijn. De nieuwe actieve fases halen bij p95 ook nog niet overal het 16,7 ms-budget van een 60 Hz-scherm.

Bronnen: [oorspronkelijke toestelmeting](device-baseline.log), [aangepaste toestelmeting](device-optimized.log).

### Simulator

Op de iPad A16-simulator met iOS 27 waren tijdens het spelen veel grotere callbackgaten zichtbaar: bij de referentie ongeveer 66–117 ms p95, en ook na de aanpassingen ongeveer 77–83 ms in de geoptimaliseerde diagnosebuild. De levelreis van die laatste build had p95 17,86 ms. Het rustende eindscherm zat rond 16,7 ms. Ook de iPhone-simulator met iOS 26.5 vertoonde grotere pieken dan het fysieke toestel.

Dit bevestigt dat de renderroute aandacht verdient, maar de simulatorwaarden zijn geen betrouwbare schatting van de uiteindelijke hardware-FPS. Er waren meerdere simulatoren actief op de host. Die bestaande gebruikerssessies zijn niet afgesloten om een kunstmatig gunstige benchmark te maken.

Bronnen: [simulatorreferentie](baseline-simulator.log), [laatste Debug-meting](final-debug-simulator.log), [geoptimaliseerde simulatormeting](release-simulator.log).

## 3. Waarom het startgeluid laat kon komen

Het startbestand bevat ongeveer 225 ms stilte voor de eerste hoorbare onset. De bestaande code sloeg die al over bij het maken van de PCM-buffer. Nogmaals de asset trimmen zou die bestaande correctie niet oplossen.

De resterende fout zat in gereedheid: de zichtbare entree kon beginnen vóór het decoderen, aanleggen van effectnodes en opstarten van de engine klaar was. In een snelle koude test liep het inplannen van de cue ongeveer **410,78 ms** achter. Met de gereedheidshandover was dit **0,02–0,03 ms in de simulator** en **0,01 ms op de fysieke iPhone**. Een koude start kan daarvoor kort op de startkaart wachten. Op het normale warme pad is dat wachten niet nodig.

Een vervallen startcue wordt niet onbeperkt later afgespeeld. De overige kortdurende effecten worden niet achteraf in een wachtrij gereproduceerd. Effecten uitzetten of de game verlaten ruimt de wachtende cue op. De effectsengine en buffers worden hergebruikt.

De I/O-buffer van 5 ms is een voorkeur. Apple benadrukt dat de werkelijke route andere waarden kan kiezen; luidspreker- en Bluetoothvertraging vallen buiten de gemeten planningsduur. Zie [Apple: preferred audio settings](https://developer.apple.com/library/archive/qa/qa1631/_index.html).

## 4. Tutorial, pauze en herstart

De tutorial gebruikt nu twee kleine herstartbare geplande acties: één voor de lesovergang en één voor de luiken. Zij bewaren de deadline met monotone tijd. Pauze of achtergronding stopt het verbruik van die tijd. Hervatten vervolgt de resterende duur; een nieuwe sessie invalideert oude acties.

Elk luik gebruikt één Canvas in plaats van vier afzonderlijke SwiftUI-stapels met gradients, schaduwen en klinknagels. De gezamenlijke voortgang en de bestaande sluitbeweging blijven behouden. Open luiken tekenen niets; lamellen buiten het zicht worden overgeslagen.

Het tutorialvuurwerk interpoleert nu de deeltjesvoortgang zelf. Voorheen konden de vertraagde bursts alleen hun onzichtbare begin- en eindtoestand berekenen en daardoor wegvallen. Bij verminderde beweging blijft de verkorte weergave behouden.

De klok bewaart daarnaast de echte resterende fractie bij pauze, in plaats van steeds naar een hele seconde omhoog af te ronden. Bij “Nog een keer” staat het nieuwe spel eerst in de introtoestand. De klok begint na de entree, volgens dezelfde handover als een eerste run.

## 5. Vragen: inhoudelijke fouten en betere antwoordplanning

De identieke kleine referentietest doorliep 8.100 rondes. Er waren geen ongeldige antwoordborden, maar wel **790 afwijkingen van de vaste rekenroute** en **13 directe herhalingen van dezelfde vraag**. Correcte rekensommen alleen waren dus onvoldoende: de les volgde niet altijd de gekozen oefenvorm.

De oude planner verlangde zes verschillende toekomstige resultaten. Dat botst bijvoorbeeld met breukoefeningen die terecht dezelfde antwoordwaarde terugbrengen. De planner zocht dan verder, herschikte vragen of week uit naar een noodvraag. De aangepaste planner laat de generator eerst de hele stage in de gekozen route maken. Vervolgens zorgt hij dat het volgende benodigde antwoord op het bord staat. Een terugkerend resultaat mag op de gebruikte knop blijven staan. Alle andere knoppen behouden hun tekst en identiteit.

Voor opvulling krijgen de oorspronkelijke, plausibele vergissingen voorrang boven kunstmatige aanvullende waarden. Het antwoordbord moet wel de toekomstige juiste antwoorden blijven dragen. Daardoor is niet iedere zichtbare foute knop een speciaal voor de huidige som ontworpen afleider; dat hoort bij het bestaande geheugenmechanisme.

De generator berekent brongewichten eenmaal, gebruikt cursors voor geschudde cycli en bewaart geschikte getallen voor decimale procentvragen. De omgekeerde percentagepool is rechtgezet. De anti-herhaalregel voor bronlevels grijpt pas in na drie eerdere keuzes, in plaats van ook op een lege historie te reageren.

De semantische antwoordparser verwerkt daarnaast `-0,5` als `-1/2`. Extra decimalen worden niet meer stil afgekapt. De game genereert maximaal twee decimalen; de parser behandelt andere notaties als tekst. De bestaande ondersteuning voor een antwoord midden in een vergelijking, zoals `1/4 = ?/12`, is behouden.

De vragen vormen geen aangetoonde grote framebottleneck. Het voorbereiden van vijftig vragen kostte in de volledige lokale audit p95 **0,892 ms**, met een gemeten maximum van **1,662 ms**. Dat zijn hostmetingen, geen bovengrens voor alle toestellen. De belangrijkste winst hier is leskwaliteit en voorspelbaar werk vóór het spelen.

## 6. Renderwerk en animaties

De Time Profiler-opname van de oorspronkelijke simulatorbuild bevatte 5.859 ms aan gewogen samples. Daarvan zat 3.359 ms in `__vImageCopyBuffer_block_invoke`: ongeveer 57% van het samplegewicht. Ook geheugenverplaatsingen waren prominent. Dit ondersteunt het beperken van beeldkopieën en tussenlagen; het is geen afzonderlijke GPU-meting of exacte CPU-utilisatie. Inclusieve stackcategorieën overlappen.

De gewone cockpit bestaat nu uit een vaste laag, feedbacklichten, een langzaam bewegende achtergrond en een aparte LED-laag. Feedback hoeft daardoor niet de romp en de bestemming opnieuw op te bouwen. De cache publiceert een revisie zodra voorbereide beelden klaar zijn, zodat een statische Canvas zijn tijdelijke gecomprimeerde assetreferentie kan vervangen door het voorbereide bitmapbeeld.

Grote asteroïdenassets worden eenmaal op de achtergrond verkleind naar maximaal 512 pixels. De primaire planeet- en karakterbeelden behouden hun resolutie. De cache gebruikt een budget van 48 MiB en maximaal veertig beelden. Dat is een cachebeleid, geen harde limiet op het totale appgeheugen: renderbuffers en systeemcaches vallen daarbuiten. Na verwijdering kan een beeld bij een volgende voorbereiding opnieuw geladen worden.

De volgende cadansen zijn bewust verschillend:

| Animatie | Normaal | Bij energiebesparing/serieuze thermische belasting |
| --- | --- | --- |
| Langzame karakterposes en zweven | 30 Hz | 20 Hz |
| Snelle levelreis | 60 Hz | 30 Hz |
| Asteroïden, sterren en decoratieve energiestromen | 8 Hz | 5 Hz |
| Reflecties op het glas | 6 Hz | 3 Hz |
| Bewegende LED-randen | 60 Hz | 30 Hz |

De eigenlijke karaktervlucht wordt buiten de pose-timeline door SwiftUI geïnterpoleerd. De 30 Hz-waarde begrenst dus niet rechtstreeks de volledige vlucht. De snelle reis gebruikte wel de posecadans en is daarom apart gezet. De frequenties zijn aangevraagde intervallen; het systeem kan minder vaak tekenen. Zie [Apple: TimelineView](https://developer.apple.com/documentation/swiftui/timelineview).

Bij pauze bewaart een gezamenlijke omgevingsklok de werkelijke fase van reflecties, stenen en licht. Hervatten laat die verder bewegen vanaf dezelfde plaats. Onder de reis worden verborgen sterren en asteroïden niet opnieuw getekend.

### Gemeten experimenten die zijn teruggedraaid

Een extra `drawingGroup` voor de vaste achtergrond gaf onvoldoende verbetering van de algemene callbacktijden. Die is verwijderd. Voorbereide, extra onscherpe asteroïdensprites voegden geheugen en code toe zonder overtuigende verbetering van de totale frametijden. Ook die cache is teruggedraaid.

Een proef met `preparingForDisplay` liet in deze simulator veel terugkerende assetconversie zien. De definitieve cache materialiseert daarom op de achtergrond eenmaal een gewoon bitmapbeeld. De profilerresultaten van dat tussenstadium zijn bewaard voor herleidbaarheid, maar gelden niet als bewijs voor een probleem dat nog in de definitieve versie zit.

Bronnen: [referentieprofiel](baseline-profile-summary.txt), [profiel van het tussenstadium](initial-profile-summary.txt). Het meten van invalidering en tekenwerk sluit aan bij [Apple: SwiftUI performance](https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance).

## 7. Verificatie

De volledige core-audit is geslaagd voor **400.950 rondes**, over alle zes onderwerpen, alle 99 levels, alle modi, alle vier Supermix-varianten en drie seeds. Daarnaast zijn gedeeltelijke stages vanaf vraag zeven en later aangevulde plannen gecontroleerd.

De audit controleert:

- mathematische correctheid, inclusief breukvergelijkingen en decimale percentages;
- het gekozen onderwerp, de toegestane Supermix-onderwerpen en het lesbereik;
- tafelvermenigvuldigers binnen 0–12;
- zes semantisch verschillende antwoordwaarden, met precies één juist antwoord;
- behoud van de vaste route bij optellen, aftrekken en tafels;
- stabiele knopidentiteiten en onveranderde niet-gebruikte knoppen binnen een stage;
- afwezigheid van direct herhaalde prompts.

Er waren **nul directe herhalingen** en geen schendingen van bovenstaande controles. De tutorialaudit slaagt voor quizkeuzes, drie tempovoorbeelden, luiken, pauze/hervatten, handovers, afscheid en annulering. Resultaten staan in [regression-results.txt](regression-results.txt).

De oorspronkelijke Release-build, de aangepaste Debug-build, de gewone aangepaste Release-build en beide geïsoleerde geoptimaliseerde toestelbuilds compileren succesvol. De diagnosehooks staan onder `#if DEBUG`; de gewone Release-build bevat de autoplay en de frameprobe niet. Zie [build-results.txt](build-results.txt).

De automatische routes bereikten het resultaat met 20/20. De tutorial is op de iPad ook met echte UI-taps doorlopen, inclusief pauze tijdens de quiz. De layout van speelveld en eindscherm is op iPad en iPhone bekeken. De screenshots dienen voor layoutcontrole, niet om vloeiendheid uit een stilstaand beeld af te leiden. Zie het [iPad-speelveld](ipad-gameplay.png) en het [iPhone-eindscherm](iphone-result.png).

## 8. Wat nog niet bewezen is en de volgende meetstap

Er is op de echte iPhone minder variatie in de actieve callbacktijden, maar nog geen bewijs voor een volledig stabiele presentatie op 60 FPS. De fysieke toestelmeting had nog pieken tot circa 37,5 ms tijdens spelen. Er is ook slechts één toesteltype onderzocht. Oude iPads, verminderde beweging, energiebesparing en verschillende audio-uitvoeren verdienen een afzonderlijke hardwarecontrole.

Instruments kon op de verbonden fysieke iPhone niet aan de testapp hechten: zowel de PID als de naam leverde “Cannot find process” op, terwijl de app wel draaide. De eigen callback- en audiologs zijn verkregen; een fysieke GPU-trace ontbreekt. Deze beperking staat in [device-profile-limitation.txt](device-profile-limitation.txt).

De volgende gerichte validatie is een Release-opname met Animation Hitches/Core Animation of Metal System Trace: eerst de rustige tutorial, daarna meerdere antwoorden en de levelreis. Daarmee kan onderscheid worden gemaakt tussen modelwerk, een dure compositing-pass en werk dat het framesysteem op de GPU uitvoert. Pas als die opname het aanwijst, zijn bijvoorbeeld het vooraf rasteriseren van een specifieke gloed of het splitsen van een nog groot tekenoppervlak gerechtvaardigd. Een volledige rendererherschrijving is met de huidige gegevens niet onderbouwd.

Voor audio is de resterende controle de hoorbare onset ten opzichte van de entree, met de ingebouwde luidspreker en met Bluetooth. De gemeten planningsduur is al vrijwel direct; de gemelde routelatency is geen volledige akoestische meting.

De analyse, timingcorrecties, vraagcorrecties en onderbouwde aanpassingen aan de renderroute zijn uitgevoerd. De resterende hardwaremetingen zijn expliciet afgebakend, zodat er geen onbewezen FPS-belofte aan deze wijzigingen wordt verbonden. De tijdelijke apps op het fysieke toestel zijn na de metingen verwijderd. Bestaande game-installaties en gebruikerswijzigingen zijn behouden.

## Bestanden en herhalen

De aangepaste productiebestanden zijn `AppAudio.swift`, `GameView.swift`, `GameViewModel.swift`, `SpaceLionPlayfield.swift`, `Tutorial.swift` en de corebestanden `RoundFactory.swift`, `QuestionGenerator.swift`, `MathTopic.swift` en `MathQuestion.swift`. `ElephantChallengeApp.swift` bevat uitsluitend de aanvullende optionele diagnose-ingang.

Testinstructies en interpretatie van de logs staan in [Tools/Performance/README.md](../../Tools/Performance/README.md). Uitvoeren vanuit de repository: `Tools/Performance/run_audits.sh`.
