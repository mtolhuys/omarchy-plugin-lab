# Testing strategy

## Evidence ladder

| Level | Command | Proves | Does not prove |
| --- | --- | --- | --- |
| Source suite | `./bin/lab fast` | Parsers, scripts, QML and JavaScript contracts, and regressions executed in a disposable guest | Global shortcuts or a complete installation |
| Plugin | `./bin/lab plugin` | Current plugin lifecycle behavior in a real disposable Hyprland and Quickshell session | A complete installation or every Omarchy application |
| Scenario | `./bin/lab plugin /path/to/plugin/tests/lab/<test>.sh` | The concrete plugin or keybinding behavior asserted by that product-owned test | Behavior the scenario does not assert |
| Broad | `./bin/lab accept` | Core shortcuts and the complete Omarchy acceptance suite | Compatibility when the ISO and source checkout come from different revisions |
| Installation | Build a local ISO, prepare a new base, then run `accept` | Packaging, installation, fixed system files, and desktop behavior together | Hardware that is not passed through to the VM |

A change is ready only when the level it affects is green. Manifest or lifecycle work requires at least `fast` and `plugin`. New global keybindings also require a scenario that sends the shortcut through QMP with `press`. Changes to systemd, `/etc`, the installer, or package contents require a local ISO.

## Product contract release gate

Before acceptance, make a small inventory of what the product publicly promises through visible controls, CLI commands, status output, documentation, and lifecycle behavior. For every promise, identify:

- the public action performed by the user;
- the observable outcome that proves success;
- the runtime boundary crossed by that action;
- the relevant failure, cancellation, and cleanup paths;
- the limitation that deliberately remains outside the claim.

Test the complete route from user action to observable outcome. A direct function call, IPC command, or synthetic fixture proves only the layer it actually crosses. Use representative real clients when behavior depends on a toolkit, compositor, or protocol. Do not add arbitrary variants unless they cover a distinct boundary.

Public state must be controllable, visible, and recoverable. State without a reachable control or meaningful feedback is not finished product behavior, even when the internal model and unit tests pass. Simplify such state before documentation and regressions accumulate around it.

Run final acceptance against one clean, committed candidate. Compare the source revision, installed revision, and loaded runtime identities. Then confirm that the README, manifest, CLI, and status output describe only behavior proven in that same candidate.

## What the default plugin test checks

`host-tests/plugin-lifecycle.sh` creates a local Git repository from `fixtures/lifecycle-plugin` inside the disposable VM and checks:

1. validation and installation through the real `omarchy-plugin-add` command;
2. discovery and enabled state in the running shell;
3. persistent registration in `~/.config/omarchy/shell.json`;
4. disablement without removing plugin files;
5. re-enablement;
6. removal, runtime unload, and configuration cleanup;
7. the absence of Hyprland configuration errors.

The run writes `host-test.log`, two lifecycle screenshots, a serial log, and the installation log to the timestamped result directory.

## Adding a product-owned scenario

Copy `host-tests/example.sh` into the product repository and define `omarchy_host_test()` there. Do not add product-specific tests or fixtures to this repository. The available helpers are:

- `press`: sends a real virtual key or chord through QMP;
- `ssh_guest`: checks ordinary guest state;
- `ssh_session`: runs a command in the active Wayland and Hyprland environment;
- `wait_for_guest_state`: waits for a bounded machine assertion;
- `capture_console`: saves a visual checkpoint.

For an absolute pointer or touch tap, a scenario can source `host-tests/helpers/pointer.sh` and call `qmp_pointer_tap <width> <height> <x> <y> [left|right|middle]`. The helper validates viewport coordinates and QMP responses; the scenario assertion must still prove that the intended control was visible and responded.

Every important user action needs a machine assertion. A screenshot is supporting evidence, not a substitute for state verification.

The harness clears notification popups inherited from the reusable base before
the product-owned scenario starts. This keeps visual checkpoints deterministic
without silencing notifications that the scenario deliberately creates later.

## Hot reload and runtime identity

A successful plugin add, update, rescan, or manifest validation proves only the state on disk. Quickshell may reject a new QML component while the old object remains visible, and Qt may cache components by URL. A scenario for a hot-loaded plugin must therefore:

1. compare the source and installed revisions and manifest versions;
2. expose a build identity from every independently loaded runtime unit, such as a service and bar widget;
3. compare those identities with the manifest version after update or rescan;
4. inspect the shell log from the reload boundary for entry-point and dependency failures;
5. assert at least one public behavior introduced or changed by the new runtime.

An old screen that merely looks plausible is not success. When current Qt or Quickshell versions demonstrably retain components by URL, version the complete executable QML and JavaScript graph as one unit. Moving only the root entry point can combine a new root with old imports.

## Pointer and bar contracts

Before implementation, inspect the current host component that mounts a widget or panel. The host may own the top pointer layer, cross-axis sizing, click registration, and forwarding API. A child `MouseArea` can therefore render correctly while never receiving input.

Click and touch behavior requires a QMP pointer action on the rendered control, followed by a machine assertion of the public effect. First confirm that the control is visible and not covered by fullscreen content or another layer. Also assert bar height and alignment; a compact width must not introduce vertical padding or a reduced hit target.
