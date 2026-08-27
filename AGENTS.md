# Omarchy Plugin Lab

This directory is the safe execution boundary for Omarchy plugin and native desktop experiments. Use the disposable VM for anything that activates a plugin, reloads Hyprland, restarts `omarchy-shell`, changes user configuration, or exercises global keyboard shortcuts. Do not perform those experiments on the host system.

All tracked documentation, comments, fixture text, diagnostics, and user-facing output must be written in English so the repository remains ready for public collaboration.

## Required workflow

1. Run `./bin/lab doctor` before a new test session.
2. Run `./bin/lab fast` for the complete repository suite inside a disposable guest. Never run `./test/all` directly on the Omarchy host.
3. Run `./bin/lab prepare` once when no reusable base image exists.
4. Run `./bin/lab plugin` for the focused, mandatory plugin lifecycle proof.
5. Run `./bin/lab plugin <host-test>` for a feature-specific plugin scenario.
6. Use `./bin/lab accept` only for the broad desktop regression suite. Its ISO and source checkout must be from compatible revisions.
7. Treat the timestamped result directory printed by the harness as the evidence source. Never claim real-session acceptance from host tests or screenshots alone.
8. Treat install/update/rescan success as file-state evidence, not runtime proof. For hot-loaded plugins, assert the loaded build identity and behavior of every independently loaded entry point, then inspect post-reload logs.
9. Treat every user-facing claim as a contract. Prove it through the public interaction a user actually performs and an observable outcome, not through an internal function or substitute path.
10. Trace an interaction through its host-owned event route before implementing it. A handler is not a feature unless the mounted runtime can deliver the event to it.
11. Do not ship hidden product states. Every state needs a discoverable control, meaningful feedback, deterministic recovery, and end-to-end coverage; otherwise simplify the state model.

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

Keep product-specific scenarios and fixtures in the product repository and pass their path to the lab command. This repository may contain only the generic lifecycle gate, repository runner, helpers, and minimal examples required to operate the lab.

Use QMP `press` for global shortcut proof. In-guest `wtype` is not evidence that Hyprland received a real global key chord.

For clickable, touchable, pointer, drag, or hover UI, send QMP pointer events to
the rendered control and assert the resulting public state. Calling its IPC or
function directly proves the backend but not hit testing. Confirm the test
precondition too: the control must not be covered by fullscreen content or
another layer.

Before calling a candidate complete, audit its README, manifest, CLI, visible labels, and status output against the tested public surface. Remove claims and concepts that have no corresponding user path. Test the exact committed candidate that will be shared; do not transfer conclusions from an earlier revision or a dirty checkout.

## Repositories

- Omarchy source under test: `/home/mtolhuijs/Projects/omarchy/plugin-integrations`
- Official ISO harness: `/home/mtolhuijs/Projects/omarchy/omarchy-iso`
- Omarchy package sources for full ISO builds: `/home/mtolhuijs/Projects/omarchy/omarchy-pkgs`

The ISO harness is on the local `plugin-lab` branch and carries the generic `--dev-link`, `--host-test`, and `--host-test-only` extensions. Inspect and preserve those changes when updating it from upstream.
