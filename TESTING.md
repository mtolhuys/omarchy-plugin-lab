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

Elke belangrijke gebruikersactie hoort een machine-assertie te hebben. Een screenshot is aanvullend bewijs, geen vervanging voor statuscontrole.

## Bekende fixturebevindingen

- De officiële Omarchy 4.0.1-ISO installeert en start in het lab, maar de geteste niet-versleutelde fixture kan bij een latere volledige reboot blijven hangen op een Limine/resume-melding. De broncode-activatie gebruikt daarom een volledige grafische logout/login, wat alle gebruikerssessie-omgevingen opnieuw opbouwt zonder deze afzonderlijke ISO-bug te maskeren.
- De huidige `quattro`-bron verwacht op enkele punten nieuwere package/app-inhoud dan de gepubliceerde 4.0.1-ISO. De gerichte pluginproef is hiervoor onafhankelijk gemaakt. Voor een betrouwbare brede regressie moet `./bin/lab build` worden gebruikt en moet uit die lokale ISO een eigen base worden gemaakt.
