# Omarchy Plugin Lab

Een lokale, disposable Omarchy-omgeving voor plugin-, Hyprland-, Quickshell- en native desktopontwikkeling zonder de dagelijkse hostinstallatie als proefkonijn te gebruiken.

## Architectuur

```text
host source checkout
        |
        | tar over localhost SSH
        v
reusable Omarchy 4.0.1 base image
        |
        | qcow2 copy-on-write overlay per run
        v
disposable KVM guest
  - dev-linked to synced source
  - fresh graphical login activates all user-session paths
  - real Hyprland + Quickshell
  - QMP virtual keyboard input
  - guest assertions over SSH
        |
        v
logs + state dumps + screenshots
```

Docker alleen kan scripts en parsers testen, maar bewijst geen compositorbindings, QML-runtime, shell-lifecycle of desktopgedrag. Het lab gebruikt daarom de officiële `omarchy-iso-test`-harness met KVM. De eenmalig geïnstalleerde basisschijf blijft schoon; iedere acceptatierun gebruikt een nieuwe copy-on-write overlay die na afloop weg kan.

## Dagelijks gebruik

Controleer de omgeving:

```bash
./bin/lab doctor
```

Draai de complete bronsuite geïsoleerd in een nieuwe VM-overlay:

```bash
./bin/lab fast
```

Ook deze tests draaien bewust niet op de host. Een deel van Omarchy's zogenaamd headless tests start Quickshell of passeert code met privilegepaden; op een dagelijks gebruikte Omarchy-sessie is dat geen acceptabel risico.

Maak eenmalig de herbruikbare Omarchy-basisschijf:

```bash
./bin/lab prepare
```

Draai daarna een volledige disposable acceptatieronde:

```bash
./bin/lab plugin
```

Dit is de dagelijkse, gerichte pluginproef. Hij synchroniseert de volledige checkout, koppelt de gast via Omarchy's dev-link aan die checkout en begint een nieuwe grafische login. Daarna bewijst hij in een echte Hyprland/Quickshell-sessie: toevoegen, inschakelen, uitschakelen, opnieuw inschakelen en verwijderen inclusief configuratie-opruiming. De basisschijf wordt niet gewijzigd.

Gebruik voor een eigen plugin-scenario dezelfde korte route:

```bash
./bin/lab plugin host-tests/mijn-plugin-test.sh
```

De brede Omarchy-regressie is een aparte test:

```bash
./bin/lab accept
```

Die test bedient ook Omarchy's standaardsneltoetsen via QMP en draait de volledige in-guest suite. Gebruik daarvoor een ISO en source checkout uit dezelfde revisie. De gepubliceerde 4.0.1-ISO en de actuele `quattro`-branch zijn inmiddels uit elkaar gelopen; verwachte applicatie- of menuwijzigingen mogen niet als pluginregressie worden geïnterpreteerd.

Voor een test die QMP-toetsen en SSH-asserties zelf coördineert:

```bash
./bin/lab accept-host host-tests/example.sh
```

`accept-host` combineert die eigen test met de brede regressiesuite. Voor normale pluginontwikkeling is `lab plugin` sneller en geeft het minder ruis.

Laat de VM na een run aan en open daarna een shell:

```bash
./bin/lab accept-keep
./bin/lab shell
```

Toon de laatst aangemaakte artifactmap:

```bash
./bin/lab latest
```

## Volledige lokale ISO-build

Normale pluginiteraties hebben geen nieuwe ISO nodig. Wanneer packaging, installatie, systemd-units of vaste systeembestanden veranderen, bouw je wel een ISO uit de lokale Omarchy- en packagecheckouts:

```bash
./bin/lab build
```

Gebruik die nieuwe ISO vervolgens via een override in `.lab.env` en maak een nieuwe base met `./bin/lab prepare --fresh`.

`lab build` laat de host-packagecache intact, maakt een checksum naast de lokale ISO en toont het exacte pad dat in `.lab.env` moet komen.

## Resources en isolatie

Het lab reserveert standaard 5 GiB RAM voor de gast, gebruikt KVM-hardwareacceleratie en forwardt alleen gast-SSH naar `127.0.0.1:2222`. Er wordt geen host-home, Wayland-socket, Docker-socket, SSH-agent of fysiek apparaat in de gast gemount. Met 16 GiB hostgeheugen blijft de computer bruikbaar, al is een volledige desktopacceptatieronde natuurlijk merkbaar.

Lokale overrides kunnen in `.lab.env`; zie `lab.env.example`. Dat bestand wordt niet gecommit.

## Bewijs, niet alleen groen licht

De officiële harness bewaart iedere run onder `omarchy-iso/test-runs/<iso>/runs/<timestamp>/`. Daar staan serial logs, install logs, screenshots en de artifacts uit de in-guest suite. Een feature is pas bewezen wanneer zowel machine-asserties als deze artifacts het verwachte gedrag laten zien.

Bij hot-reloadbare Quickshell-plugins betekent een geslaagde
installatie/update/rescan alleen dat de bestanden en configuratie zijn
bijgewerkt. De draaiende shell kan een vervangend component afwijzen of een oud
component uit de QML-cache behouden. Laat een scenario daarom de geladen
service- en widgetbuild vergelijken met de geïnstalleerde manifestversie,
controleer de logs na de reload en bewijs de nieuwe werking. Voor klik- of
touchbediening moet QMP daadwerkelijk op het zichtbare control klikken; IPC
alleen bewijst de backend niet.

Een overlay met bewijs is momenteel grofweg 0,5–0,6 GiB. Bewaar geslaagde referentieruns en ruim oude mislukte timestampmappen bewust op wanneer het bewijs niet meer nodig is; de herbruikbare `base.qcow2` hoort te blijven staan.

Zie [TESTING.md](TESTING.md) voor de bewijsladder, bekende fixturebeperkingen en een recept voor nieuwe scenario's.
