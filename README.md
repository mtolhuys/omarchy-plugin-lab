# Omarchy Plugin Lab

A local, disposable Omarchy environment for plugin, Hyprland, Quickshell, and native desktop development without using the daily host installation as a test target.

## Architecture

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

Docker can test scripts and parsers, but it cannot prove compositor bindings, QML runtime behavior, shell lifecycle, or desktop interactions. The lab therefore uses the official `omarchy-iso-test` harness with KVM. The reusable installed base remains clean; every acceptance run uses a new copy-on-write overlay that can be discarded afterward.

## Daily use

Check the environment:

```bash
./bin/lab doctor
```

Run the complete source suite in an isolated VM overlay:

```bash
./bin/lab fast
```

These tests deliberately do not run on the host. Some nominally headless Omarchy tests start Quickshell or cross privileged code paths, which is not an acceptable risk in a daily desktop session.

Create the reusable Omarchy base image once:

```bash
./bin/lab prepare
```

Then run the focused plugin lifecycle test:

```bash
./bin/lab plugin
```

This is the routine plugin test. It synchronizes the complete checkout, dev-links the guest to that checkout, and starts a fresh graphical login. In a real Hyprland and Quickshell session it then proves add, enable, disable, re-enable, and removal behavior, including configuration cleanup. The base image is not modified.

Use the same route for a feature-specific plugin scenario:

```bash
./bin/lab plugin host-tests/my-plugin-test.sh
```

The broad Omarchy regression suite is separate:

```bash
./bin/lab accept
```

It also operates Omarchy's standard shortcuts through QMP and runs the complete in-guest suite. Use an ISO and source checkout from compatible revisions. The published 4.0.1 ISO and the current `quattro` branch have diverged, so expected application or menu differences must not be misclassified as plugin regressions.

To coordinate QMP input and SSH assertions in a custom broad acceptance test:

```bash
./bin/lab accept-host host-tests/example.sh
```

`accept-host` combines the custom test with the broad regression suite. For normal plugin development, `lab plugin` is faster and produces less unrelated noise.

Keep the VM running after a test and open a shell:

```bash
./bin/lab accept-keep
./bin/lab shell
```

Show the latest artifact directory:

```bash
./bin/lab latest
```

## Full local ISO build

Normal plugin iterations do not require a new ISO. Build one from the local Omarchy and package checkouts when packaging, installation, systemd units, or fixed system files change:

```bash
./bin/lab build
```

Select the new ISO through an override in `.lab.env`, then create a new base with `./bin/lab prepare --fresh`.

`lab build` leaves the host package cache intact, creates a checksum next to the local ISO, and prints the exact path to place in `.lab.env`.

## Resources and isolation

The lab reserves 5 GiB of guest memory by default, uses KVM hardware acceleration, and forwards only guest SSH to `127.0.0.1:2222`. It does not mount the host home, Wayland socket, Docker socket, SSH agent, or any physical device into the guest. A machine with 16 GiB of host memory remains usable, although a complete desktop acceptance run is noticeable.

Local overrides belong in `.lab.env`; see `lab.env.example`. That file is not committed.

## Evidence, not just a green result

The official harness stores every run under `omarchy-iso/test-runs/<iso>/runs/<timestamp>/`. Each directory contains serial logs, installation logs, screenshots, and artifacts from the in-guest suite. A feature is proven only when machine assertions and the collected evidence both support the expected behavior.

For hot-reloadable Quickshell plugins, a successful install, update, or rescan proves only that files and configuration changed. The running shell may reject a replacement component or retain an old component in the QML cache. A scenario must therefore compare loaded service and widget builds with the installed manifest version, inspect logs after the reload boundary, and prove the new behavior. Click and touch behavior must be exercised on the visible control through QMP; IPC alone proves only the backend.

A run overlay currently uses roughly 0.5–0.6 GiB. Preserve successful reference runs and deliberately remove obsolete failed run directories when their evidence is no longer useful. Keep the reusable `base.qcow2`.

See [TESTING.md](TESTING.md) for the evidence ladder, known fixture limitations, and the recipe for new scenarios.
