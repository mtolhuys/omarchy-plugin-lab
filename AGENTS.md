# Omarchy Plugin Lab

This directory is the safe execution boundary for Omarchy plugin and native desktop experiments. Use the disposable VM for anything that activates a plugin, reloads Hyprland, restarts `omarchy-shell`, changes user configuration, or exercises global keyboard shortcuts. Do not perform those experiments on the host system.

## Required workflow

1. Run `./bin/lab doctor` before a new test session.
2. Run `./bin/lab fast` for the complete repository suite inside a disposable guest. Never run `./test/all` directly on the Omarchy host.
3. Run `./bin/lab prepare` once when no reusable base image exists.
4. Run `./bin/lab plugin` for the focused, mandatory plugin lifecycle proof.
5. Run `./bin/lab plugin <host-test>` for a feature-specific plugin scenario.
6. Use `./bin/lab accept` only for the broad desktop regression suite. Its ISO and source checkout must be from compatible revisions.
7. Treat the timestamped result directory printed by the harness as the evidence source. Never claim real-session acceptance from host tests or screenshots alone.

The VM commands synchronize the complete source checkout, dev-link the disposable guest to it, and start a fresh graphical login so every user-session layer reads the checkout. `plugin` runs only the requested host-driven scenario. `accept` additionally runs hardware-level shortcut smoke tests and the broad in-guest Omarchy suite. A run overlay is disposable; the reusable installed base must remain unchanged.

## Safety

- Never point `OMARCHY_LAB_SOURCE` at the host's installed `/usr/share/omarchy` or at `~/.config`.
- Never run repository test entrypoints directly against the logged-in host session; even nominally headless tests can discover the live shell or privileged host paths.
- Never mount the host home directory read-write into the guest.
- Keep guest networking behind QEMU user networking and bind SSH forwarding to localhost.
- Do not pass host secrets, SSH agents, Wayland sockets, Docker sockets, or hardware devices into the guest.
- Do not delete or rewrite the reusable base image from an experiment. Rebuild it only through `./bin/lab prepare --fresh`.
- A broken or destructive test belongs in a new overlay and must clean up guest state with traps where practical.
- If a test requires host package changes or privileges, stop and ask; ordinary plugin development should not.

## Host-driven tests

A host test is a trusted Bash file defining `omarchy_host_test()`. The official ISO harness sources it after the disposable guest has booted from the synchronized dev checkout. It may use the harness helpers `press`, `ssh_guest`, `ssh_session`, `capture_console`, `wait_for_guest_state`, and the artifact path in `RUN_DIR`.

Use QMP `press` for global shortcut proof. In-guest `wtype` is not evidence that Hyprland received a real global key chord.

## Repositories

- Omarchy source under test: `/path/to/omarchy`
- Official ISO harness: `/path/to/omarchy-iso`
- Omarchy package sources for full ISO builds: `/path/to/omarchy-pkgs`

The ISO harness is on the local `plugin-lab` branch and carries the generic `--dev-link`, `--host-test`, and `--host-test-only` extensions. Inspect and preserve those changes when updating it from upstream.
