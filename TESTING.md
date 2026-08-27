# Teststrategie

## De bewijsladder

| Niveau | Commando | Bewijst | Bewijst niet |
|---|---|---|---|
| Bronsuite | `./bin/lab fast` | Parsers, scripts, QML/JS-contracttests en regressies, uitgevoerd in een disposable gast | Globale toetsen of een volledige installatie |
| Plugin | `./bin/lab plugin` | De actuele plugin lifecycle in een echte disposable Hyprland/Quickshell-sessie | Een complete installatie of iedere Omarchy-app |
| Scenario | `./bin/lab plugin host-tests/<test>.sh` | Het concrete plugin- of keybindingsgedrag uit die test | Niet-geassert gedrag |
| Breed | `./bin/lab accept` | Kernshortcuts en de volledige Omarchy acceptance suite | Compatibiliteit als ISO en bron verschillende revisies hebben |
| Installatie | lokale ISO bouwen, nieuwe base voorbereiden, daarna `accept` | Packaging, installatie, vaste systeembestanden en desktopgedrag samen | Hardware die niet aan de VM is doorgegeven |

Een wijziging is pas klaar wanneer de laag waarop hij ingrijpt groen is. Manifest- of lifecyclewerk vereist minimaal `fast` plus `plugin`. Nieuwe globale keybindings vereisen daarnaast een scenario dat de toets met `press` via QMP verstuurt. Wijzigingen aan systemd, `/etc`, installer of package-inhoud vereisen een lokale ISO.

## Productcontract als releasepoort

Maak vóór de acceptatieronde een kleine inventaris van wat het product publiek belooft: zichtbare bediening, CLI, status, documentatie en lifecycle. Voor iedere belofte moet duidelijk zijn:

- welke publieke handeling de gebruiker uitvoert;
- welke waarneembare uitkomst het succes bewijst;
- welke runtimegrens de handeling passeert;
- welke fout-, annulerings- en opruimpaden relevant zijn;
- welke beperking bewust buiten de claim valt.

Test de volledige route van gebruikershandeling tot uitkomst. Een directe functieaanroep, IPC-opdracht of synthetische fixture bewijst alleen de laag die zij daadwerkelijk passeert. Gebruik representatieve echte clients wanneer gedrag van een toolkit, compositor of protocol afhangt; voeg niet willekeurig meer varianten toe wanneer ze geen nieuwe grens afdekken.

Publieke toestand moet bedienbaar, zichtbaar en herstelbaar zijn. Een toestand zonder bereikbare bediening of betekenisvolle feedback is geen af productgedrag, ook niet wanneer het interne model en de unit-tests kloppen. Vereenvoudig zulke toestand voordat er documentatie en regressies omheen groeien.

Voer de laatste acceptatie uit op één schoon, gecommit kandidaat. Vergelijk bronrevisie, geïnstalleerde revisie en geladen runtime-identiteiten, en controleer daarna opnieuw dat README, manifest, CLI en status uitsluitend gedrag beschrijven dat in diezelfde kandidaat is bewezen.

## Wat de standaard pluginproef controleert

`host-tests/plugin-lifecycle.sh` maakt binnen de wegwerp-VM een lokale gitrepository van `fixtures/lifecycle-plugin` en controleert vervolgens:

1. validatie en installatie via de echte `omarchy-plugin-add`;
2. discovery en enabled state in de draaiende shell;
3. persistente registratie in `~/.config/omarchy/shell.json`;
4. uitschakelen zonder pluginbestanden te verwijderen;
5. opnieuw inschakelen;
6. verwijderen, runtime unload en configuratie-opruiming;
7. afwezigheid van Hyprland-configuratiefouten.

De run schrijft `host-test.log`, twee lifecycle-screenshots, een seriële log en de installatielog naar de timestampmap die aan het eind wordt getoond.

## Een scenario toevoegen

Kopieer `host-tests/example.sh` en definieer `omarchy_host_test()`. Beschikbare helpers zijn:

- `press`: verstuurt een echte virtuele toets of chord via QMP;
- `ssh_guest`: controleert gewone gaststatus;
- `ssh_session`: voert een opdracht uit met de actieve Wayland/Hyprland-omgeving;
- `wait_for_guest_state`: wacht begrensd op een machine-assertie;
- `capture_console`: bewaart een visueel checkpoint.

Voor een absolute pointer/touch-tap kan een scenario
`host-tests/helpers/pointer.sh` sourcen en
`qmp_pointer_tap <breedte> <hoogte> <x> <y> [left|right|middle]` gebruiken. De
helper valideert de viewportcoördinaten en QMP-responses; de scenarioassertie
moet nog steeds bewijzen dat het bedoelde control zichtbaar was en reageerde.

Elke belangrijke gebruikersactie hoort een machine-assertie te hebben. Een screenshot is aanvullend bewijs, geen vervanging voor statuscontrole.

## Hot reload en runtime-identiteit

Een geslaagde `plugin add`, `plugin update`, rescan of manifestvalidatie bewijst
alleen de toestand op schijf. Quickshell kan een nieuw QML-component afwijzen
terwijl het oude object zichtbaar blijft, en Qt kan componenten per URL cachen.
Een scenario voor een hot-loaded plugin hoort daarom:

1. de bron- en geïnstalleerde revisie/manifestversie te vergelijken;
2. iedere onafhankelijk geladen runtime-eenheid een build-identiteit te laten
   rapporteren, bijvoorbeeld service én barwidget;
3. die identiteiten na update/rescan te vergelijken met de manifestversie;
4. de shell-log vanaf de reloadgrens te controleren op entrypoint- en
   dependencyfouten;
5. minstens één nieuw of gewijzigd publiek gedrag te asserten.

Een oud scherm dat er aannemelijk uitziet is geen succes. Wanneer actuele
Qt/Quickshell-versies aantoonbaar componenten op URL vasthouden, versioneer dan
de volledige uitvoerbare QML/JS-graaf als één eenheid. Alleen het root-entrypoint
verplaatsen kan een nieuwe root met oude imports combineren.

## Pointer- en barcontracten

Lees vóór implementatie de actuele hostcomponent die een widget of panel
mount. De host kan de bovenste pointerlaag, cross-axis-afmetingen,
clickregistratie en forwarding-API bezitten. Een eigen `MouseArea` kan daardoor
correct renderen maar nooit input krijgen.

Klik- en touchgedrag vereist een QMP-pointeractie op het gerenderde control,
gevolgd door een machine-assertie van het publieke effect. Controleer vooraf dat
het control werkelijk zichtbaar en niet door fullscreencontent of een andere
layer bedekt is. Assert daarnaast de barhoogte/uitlijning; een compacte breedte
mag geen verticale padding of verkleind hit target introduceren.

## Bekende fixturebevindingen

- De officiële Omarchy 4.0.1-ISO installeert en start in het lab, maar de geteste niet-versleutelde fixture kan bij een latere volledige reboot blijven hangen op een Limine/resume-melding. De broncode-activatie gebruikt daarom een volledige grafische logout/login, wat alle gebruikerssessie-omgevingen opnieuw opbouwt zonder deze afzonderlijke ISO-bug te maskeren.
- De huidige `quattro`-bron verwacht op enkele punten nieuwere package/app-inhoud dan de gepubliceerde 4.0.1-ISO. De gerichte pluginproef is hiervoor onafhankelijk gemaakt. Voor een betrouwbare brede regressie moet `./bin/lab build` worden gebruikt en moet uit die lokale ISO een eigen base worden gemaakt.
- De 4.0.1-fixture logt bij iedere `wtype`-virtual-keyboardcyclus `Key <LFSH> added to map for multiple modifiers`. Omarchy's XKB-optie `shift:both_capslock_cancel` geeft de Shift-toetsen bewust zowel `Shift_L` als `Caps_Lock`; de oudere libxkbcommon in deze fixture waarschuwt wanneer de compositor die keymap opnieuw compileert. Dit is geen achtergebleven modifier. De tabletproef controleert dat onderscheid door een fysieke QMP Super+Space direct na annulering, backend failure, hide, update, disable en removal te laten werken.
