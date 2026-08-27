#!/bin/bash

# Tablet keyboard acceptance for the private disposable VM lab.

omarchy_host_test() {
  local plugin_dir
  local fixture_dir
  local remote_plugin_dir="${TABLET_PLUGIN_GUEST_DIR:-/tmp/omarchy-tablet-mode}"
  local remote_fixture_dir="/tmp/omarchy-tablet-mode-fixtures"
  local probe_address
  local target_address
  local expected_version
  plugin_dir=${TABLET_PLUGIN_SOURCE:?Set TABLET_PLUGIN_SOURCE to the tablet plugin checkout}
  fixture_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/tablet-mode" && pwd)"
  [[ -d $plugin_dir/.git && -f $plugin_dir/manifest.json ]] || {
    printf 'Invalid TABLET_PLUGIN_SOURCE: %s\n' "$plugin_dir" >&2
    return 1
  }
  expected_version=$(jq -er '.version' "$plugin_dir/manifest.json") || return 1

  log "Staging Omarchy Tablet Mode in the disposable guest"
  tar -C "$plugin_dir" -cf - . | ssh_guest \
    "rm -rf ${remote_plugin_dir} && mkdir -p ${remote_plugin_dir} && tar -C ${remote_plugin_dir} -xf -" || return 1
  tar -C "$fixture_dir" -cf - . | ssh_guest \
    "rm -rf ${remote_fixture_dir} && mkdir -p ${remote_fixture_dir} && tar -C ${remote_fixture_dir} -xf -" || return 1
  ssh_guest "git -C ${remote_plugin_dir} rev-parse --verify HEAD >/dev/null && \
    git -C ${remote_plugin_dir} diff --quiet && \
    git -C ${remote_plugin_dir} diff --cached --quiet" || return 1

  log "Recording the installed input backend and real-toolkit targets"
  ssh_guest "pacman -Q wtype; wtype 2>&1 || true; \
    printf 'browsers='; command -v chromium || command -v google-chrome-stable || command -v omarchy-webapp-handler || true; \
    printf 'gtk-launchers='; command -v gtk4-demo || command -v gtk3-demo || command -v yad || command -v zenity || command -v gjs || true; \
    python -c 'import gi; print(\"python-gi=\" + gi.__file__)' 2>/dev/null || true; \
    pacman -Q | grep -E '^(gtk[34]|python-gobject|gjs|zenity|yad) ' || true" || return 1

  ssh_guest "cd ${remote_plugin_dir} && ./bin/test" || return 1
  ssh_guest "omarchy-plugin-validate ${remote_plugin_dir}" || return 1
  ssh_guest "cc -O2 -Wall -Wextra \
    ${remote_fixture_dir}/gtk-input-target.c \
    -o /tmp/omarchy-tablet-gtk-target \
    \$(pkg-config --cflags --libs gtk4)" || return 1

  log "Installing disposable Hyprland and wtype fixtures in the run overlay"
  ssh_guest "echo '$GUEST_PASSWORD' | sudo -S install -Dm755 \
    ${remote_fixture_dir}/hyprctl-detector-fixture /usr/local/bin/hyprctl && \
    echo '$GUEST_PASSWORD' | sudo -S install -Dm755 \
    ${remote_fixture_dir}/wtype-fixture /usr/local/bin/wtype" || return 1
  ssh_session "printf '%s\n' '{\"switches\":[{\"name\":\"Asus WMI hotkeys\"}],\"keyboards\":[{\"name\":\"at-translated-set-2-keyboard\"},{\"name\":\"asustek-computer-inc.-n-key-device\"}]}' \
      > /tmp/omarchy-tablet-detector-devices.json; \
    omarchy-restart-shell" || return 1
  wait_for_guest_state "shell restarts with the detector fixture on PATH" 20 ssh_session \
    "omarchy-shell shell ping >/dev/null && hyprctl -j devices | jq -e '.switches[0].name == \"Asus WMI hotkeys\"'" || return 1
  ssh_session "hyprctl -j getoption input:kb_options | jq -e '.str | contains(\"shift:both_capslock_cancel\")'" || return 1
  printf 'ok - guest exercises Omarchy shift:both_capslock_cancel XKB option\n'

  log "Selecting the 1280x800 minimum 16:10 viewport"
  ssh_session 'monitor=$(hyprctl -j monitors | jq -r ".[0].name"); hyprctl eval "hl.monitor({ output = \"$monitor\", mode = \"1280x800@60\", position = \"0x0\", scale = 1 })" >/dev/null' || return 1
  wait_for_guest_state "minimum 16:10 viewport is active" 15 ssh_session \
    "hyprctl -j monitors | jq -e '.[0].width == 1280 and .[0].height == 800'" || return 1

  log "Installing and enabling through the real plugin CLI"
  ssh_session "rm -rf \"\$HOME/.config/omarchy/plugins/dev.omarchy.tablet-mode\"; \
    omarchy-plugin-add ${remote_plugin_dir} --enable --yes" || return 1
  wait_for_guest_state "tablet mode plugin is installed and enabled" 20 ssh_session \
    "test -f \"\$HOME/.config/omarchy/plugins/dev.omarchy.tablet-mode/manifest.json\" && \
     omarchy-plugin-list --json | jq -e 'any(.[]; .id == \"dev.omarchy.tablet-mode\" and .enabled == true)' && \
     omarchy-shell tablet-mode status | jq -e --arg build '$expected_version' '.runtimeBuild == \$build and .widgetBuild == \$build and .mode == \"auto\" and .visible == false and .layout == \"en-us\" and .detector.source == \"hyprland-devices\"'" || return 1
  ssh_session "test \"\$(git -C \"\$HOME/.config/omarchy/plugins/dev.omarchy.tablet-mode\" rev-parse HEAD)\" = \
    \"\$(git -C ${remote_plugin_dir} rev-parse HEAD)\" && \
    TABLET_PLUGIN_ROOT=${remote_plugin_dir} ${remote_fixture_dir}/verify-live-update" || return 1

  log "Proving Auto follows live attach, detach and reattach inventory transitions"
  ssh_session "printf '%s\n' '{\"switches\":[{\"name\":\"Asus WMI hotkeys\"}],\"keyboards\":[{\"name\":\"at-translated-set-2-keyboard\"}]}' \
    > /tmp/omarchy-tablet-detector-devices.json" || return 1
  wait_for_guest_state "Auto shows after the typing keyboard detaches" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"auto\" and .detector.active == true and .visible == true' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 1'" || return 1
  ssh_session "printf '%s\n' '{\"switches\":[{\"name\":\"Asus WMI hotkeys\"}],\"keyboards\":[{\"name\":\"at-translated-set-2-keyboard\"},{\"name\":\"asustek-computer-inc.-n-key-device\"}]}' \
    > /tmp/omarchy-tablet-detector-devices.json" || return 1
  wait_for_guest_state "Auto hides after the typing keyboard reattaches" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"auto\" and .detector.active == false and .visible == false' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 0'" || return 1

  log "Proving forced On remains distinct from Auto"
  ssh_session "omarchy-shell tablet-mode mode on | grep -qx ok" || return 1
  wait_for_guest_state "forced On shows regardless of detector state" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"on\" and .policyLabel == \"ON · FORCED\" and .visible == true'" || return 1
  ssh_session "omarchy-shell tablet-mode mode auto | grep -qx ok" || return 1
  wait_for_guest_state "Auto returns to the inactive VM detector" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"auto\" and (.policyLabel | startswith(\"AUTO · \")) and .visible == false'" || return 1

  ssh_session "rm -f /tmp/tablet-input.hex /tmp/tablet-target.log; \
    omarchy-launch-tui --app-id=tablet-test \
      python ${remote_fixture_dir}/input-target.py /tmp/tablet-input.hex \
      >/tmp/tablet-target.log 2>&1 &" || return 1
  wait_for_guest_state "controlled input target has keyboard focus" 20 ssh_session \
    "hyprctl -j activewindow | jq -e '.class == \"tablet-test\"'" || return 1
  target_address=$(ssh_session "hyprctl -j activewindow | jq -r '.address'") || return 1
  capture_console "success-tablet-01-hidden-1280x800"

  log "Applying an asymmetric bottom gap matching the physical-host regression"
  ssh_session "hyprctl eval 'hl.config({ general = { gaps_out = { top = 10, right = 10, bottom = 30, left = 10 } } }); hl.exec_scheduled_prop_refresh_immediately()' >/dev/null" || return 1
  wait_for_guest_state "asymmetric 30px bottom gap is active" 10 ssh_session \
    "hyprctl -j getoption general:gaps_out | jq -e '.css | [scan(\"[0-9]+\") | tonumber] | .[2] == 30'" || return 1

  log "Adding an effective workspace override that configuration-only compensation cannot see"
  ssh_session 'workspace=$(hyprctl -j activeworkspace | jq -r ".id"); hyprctl eval "hl.workspace_rule({ workspace = \"$workspace\", gaps_out = { top = 10, right = 10, bottom = 50, left = 10 } }); hl.exec_scheduled_prop_refresh_immediately()" >/dev/null' || return 1
  wait_for_guest_state "workspace override adds the 20px effective remainder" 10 ssh_session \
    "client_bottom=\$(hyprctl -j activewindow | jq '.at[1] + .size[1]'); test \"\$client_bottom\" -le 750" || return 1

  log "Putting the controlled target in fullscreen to exercise reversible avoidance"
  ssh_session "hyprctl eval 'hl.dispatch(hl.dsp.window.fullscreen({ mode = \"fullscreen\", action = \"set\" }))' >/dev/null" || return 1
  wait_for_guest_state "controlled target enters fullscreen" 10 ssh_session \
    "hyprctl -j activewindow | jq -e '.fullscreen > 0'" || return 1

  log "Forcing tablet mode through public IPC"
  ssh_session "omarchy-shell tablet-mode mode on | grep -qx ok" || return 1
  wait_for_guest_state "keyboard layer appears in forced-on mode" 15 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"on\" and .policyLabel == \"ON · FORCED\" and .tabletActive == true and .visible == true' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 1' && \
     hyprctl -j activewindow | jq -e '.fullscreen == 0'" || return 1
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  capture_console "success-tablet-02-visible-1280x800"

  # QEMU exposes an absolute USB tablet. These events exercise the real
  # layer-surface pointer path; each tap is followed by a bounded pause so the
  # deliberately single-flight wtype backend has completed before the next.
  tap_at() {
    local width="$1" height="$2" x="$3" y="$4" pause="${5:-0.4}" qx qy response
    qx=$((x * 32767 / (width - 1)))
    qy=$((y * 32767 / (height - 1)))
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$qx}},
      {\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$qy}}
    ]}")
    if grep -q '"error"' <<<"$response"; then
      printf 'QMP absolute move failed: %s\n' "$response" >&2
      return 1
    fi
    sleep 0.1
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"left\"}}
    ]}")
    if grep -q '"error"' <<<"$response"; then
      printf 'QMP pointer press failed: %s\n' "$response" >&2
      return 1
    fi
    sleep 0.12
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"left\"}}
    ]}")
    if grep -q '"error"' <<<"$response"; then
      printf 'QMP pointer release failed: %s\n' "$response" >&2
      return 1
    fi
    sleep "$pause"
  }

  long_press_at() {
    local width="$1" height="$2" x="$3" y="$4" qx qy response
    qx=$((x * 32767 / (width - 1)))
    qy=$((y * 32767 / (height - 1)))
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$qx}},
      {\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$qy}}
    ]}")
    if grep -q '"error"' <<<"$response"; then
      printf 'QMP long-press move failed: %s\n' "$response" >&2
      return 1
    fi
    sleep 0.1
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"left\"}}
    ]}")
    if grep -q '"error"' <<<"$response"; then
      printf 'QMP long press failed: %s\n' "$response" >&2
      return 1
    fi
    sleep 1.5
    response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
      {\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"left\"}}
    ]}")
    if grep -q '"error"' <<<"$response"; then
      printf 'QMP long release failed: %s\n' "$response" >&2
      return 1
    fi
    wait_for_guest_state "long press opens the developer alternative" 5 ssh_session \
      "omarchy-shell tablet-mode status | jq -e '.alternatesVisible == true'" || return 1
  }

  prove_physical_super_space() {
    local checkpoint="$1"
    press meta_l-spc || return 1
    wait_for_guest_state "$checkpoint: physical Super+Space opens the menu" 10 ssh_session \
      "hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-menu\")] | length >= 1'" || return 1
    press meta_l-spc || return 1
    wait_for_guest_state "$checkpoint: physical Super+Space closes the menu" 10 ssh_session \
      "hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-menu\")] | length == 0'" || return 1
  }

  log "Toggling through the real bar hit target"
  ssh_session "omarchy-shell tablet-mode hide >/dev/null" || return 1
  wait_for_guest_state "keyboard is hidden before bar toggle" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"off\" and .policyLabel == \"OFF\" and .visible == false' && \
     hyprctl -j activewindow | jq -e '.fullscreen > 0'" || return 1
  ssh_session "hyprctl eval 'hl.dispatch(hl.dsp.window.fullscreen({ action = \"unset\" }))' >/dev/null" || return 1
  wait_for_guest_state "bar is exposed for pointer toggle" 10 ssh_session \
    "hyprctl -j activewindow | jq -e '.fullscreen == 0'" || return 1
  tap_at 1280 800 1179 13 || return 1
  wait_for_guest_state "bar click shows the keyboard" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"on\" and .policyLabel == \"ON · FORCED\" and .visible == true' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 1'" || return 1
  wait_for_guest_state "measured seam correction activates for the workspace override" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.seamCorrection > 0'" || return 1
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  ssh_session "client_bottom=\$(hyprctl -j activewindow | jq '.at[1] + .size[1]'); \
    keyboard_top=\$(hyprctl -j layers | jq '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | first | (.y // .geometry[1])'); \
    delta=\$((client_bottom - keyboard_top)); \
    printf 'client_bottom=%s keyboard_top=%s delta=%s\\n' \"\$client_bottom\" \"\$keyboard_top\" \"\$delta\"; \
    test \"\$delta\" -ge -2 && test \"\$delta\" -le 2" || return 1
  printf 'ok - tiled client meets the keyboard edge despite asymmetric bottom gaps\n'
  capture_console "success-tablet-02b-bar-click-1280x800"

  log "Proving compositor shortcuts from the touch keyboard"
  ssh_session "omarchy-launch-tui --app-id=tablet-shortcut-probe sleep 120 >/tmp/tablet-shortcut-probe.log 2>&1 &" || return 1
  wait_for_guest_state "shortcut probe takes focus above the original terminal" 15 ssh_session \
    "hyprctl -j activewindow | jq -e '.class == \"tablet-shortcut-probe\"'" || return 1
  probe_address=$(ssh_session "hyprctl -j activewindow | jq -r '.address'") || return 1
  test "$probe_address" != "$target_address" || return 1
  tap_at 1280 800 255 767 || return 1      # Alt
  tap_at 1280 800 108 608 || return 1      # Alt+Tab
  wait_for_guest_state "Alt+Tab cycles away from the shortcut probe" 10 ssh_session \
    "test \"\$(hyprctl -j activewindow | jq -r '.address')\" != '$probe_address' && \
     omarchy-shell tablet-mode status | jq -e '.busy == false and ([.modifiers[]] | any) == false'" || {
      ssh_session "printf 'active after Alt+Tab: '; hyprctl -j activewindow | jq -c '{address,class,title}'; \
        printf 'tablet status: '; omarchy-shell tablet-mode status"
      return 1
    }
  ssh_session "hyprctl dispatch 'hl.dsp.focus({ window = \"address:$target_address\" })' >/dev/null" || return 1
  wait_for_guest_state "original terminal is focused for the multi-modifier shortcut" 10 ssh_session \
    "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  tap_at 1280 800 367 767 || return 1      # Super
  tap_at 1280 800 600 767 || return 1      # Super+Space
  wait_for_guest_state "touch Super+Space opens the Omarchy menu without wtype" 10 ssh_session \
    "hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-menu\")] | length >= 1' && \
     omarchy-shell tablet-mode status | jq -e '.busy == false and ([.modifiers[]] | any) == false'" || return 1
  ssh_session "omarchy-menu toggle >/dev/null" || return 1
  wait_for_guest_state "touch Super+Space menu closes cleanly" 10 ssh_session \
    "hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-menu\")] | length == 0'" || return 1
  tap_at 1280 800 150 767 || return 1      # Ctrl
  tap_at 1280 800 125 710 || return 1      # Shift
  tap_at 1280 800 367 767 || return 1      # Super
  wait_for_guest_state "three-modifier shortcut state is visibly latched" 5 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.modifiers.ctrl and .modifiers.shift and .modifiers.super and (.modifiers.alt | not)'" || return 1
  tap_at 1280 800 600 767 || return 1      # Super+Shift+Ctrl+Space
  wait_for_guest_state "Super+Shift+Ctrl+Space opens the Omarchy theme menu" 10 ssh_session \
    "hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length >= 1' && \
     omarchy-shell tablet-mode status | jq -e '.busy == false and ([.modifiers[]] | any) == false'" || {
      ssh_session "printf 'tablet status after theme chord: '; omarchy-shell tablet-mode status; \
        printf 'theme layers: '; hyprctl -j layers | jq -c '[.. | objects | select(.namespace? == \"omarchy-image-selector\")]'"
      return 1
    }
  capture_console "success-tablet-02d-touch-shortcut-theme-menu"
  ssh_session "omarchy-shell shell hide omarchy.image-picker >/dev/null; hyprctl eval 'hl.dispatch(hl.dsp.window.close({ window = \"address:$probe_address\" }))' >/dev/null" || return 1
  wait_for_guest_state "theme menu closes without changing terminal focus" 10 ssh_session \
    "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-image-selector\")] | length == 0'" || return 1

  log "Proving the bar is the sole touch control and restores Auto when detached"
  ssh_session "printf '%s\n' '{\"switches\":[{\"name\":\"Asus WMI hotkeys\"}],\"keyboards\":[{\"name\":\"at-translated-set-2-keyboard\"}]}' \
    > /tmp/omarchy-tablet-detector-devices.json" || return 1
  wait_for_guest_state "forced On stays visible after detector reports detach" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"on\" and .detector.active == true and .visible == true'" || return 1
  tap_at 1280 800 1179 13 || return 1
  wait_for_guest_state "bright bar icon dismisses the keyboard" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"off\" and .visible == false'" || return 1
  capture_console "success-tablet-02c-dismissed-1280x800"
  tap_at 1280 800 1179 13 || return 1
  wait_for_guest_state "dim bar icon restores detector-driven Auto while detached" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"auto\" and .detector.active == true and .visible == true'" || return 1

  log "Typing representative printable, modifier, navigation and control keys"
  tap_at 1280 800 123 659 || return 1      # a
  tap_at 1280 800 125 710 || return 1      # Shift
  ssh_session "printf 'QMP pointer after Shift: '; hyprctl cursorpos" || return 1
  capture_console "debug-tablet-pointer-after-shift"
  wait_for_guest_state "Shift state is visible" 5 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.shift == true'" || return 1
  capture_console "success-tablet-03-shift-1280x800"
  tap_at 1280 800 540 715 || return 1      # b -> B, consumes Shift
  tap_at 1280 800 125 710 || return 1      # Shift
  tap_at 1280 800 160 557 || return 1      # 1 -> !, consumes Shift
  tap_at 1280 800 600 767 || return 1      # Space
  tap_at 1280 800 1050 767 || return 1     # Left
  tap_at 1280 800 1210 557 || return 1     # Backspace
  tap_at 1280 800 1220 767 || return 1     # Right
  tap_at 1280 800 108 608 || return 1      # Tab
  tap_at 1280 800 68 557 || return 1       # Escape
  tap_at 1280 800 150 767 || return 1      # Ctrl latch
  wait_for_guest_state "Ctrl is visibly latched" 5 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.modifiers.ctrl == true'" || return 1
  tap_at 1280 800 410 715 || return 1      # Ctrl+C
  tap_at 1280 800 255 767 || return 1      # Alt latch
  wait_for_guest_state "Alt is visibly latched" 5 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.modifiers.alt == true'" || return 1
  tap_at 1280 800 326 715 || return 1      # Alt+X
  tap_at 1280 800 367 767 || return 1      # Super latch
  wait_for_guest_state "Super is visibly latched without firing a global shortcut" 5 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.modifiers.super == true'" || return 1
  capture_console "success-tablet-03b-super-latched-1280x800"
  tap_at 1280 800 367 767 || return 1      # cancel Super
  prove_physical_super_space "modifier cancellation" || return 1
  tap_at 1280 800 1128 659 || return 1     # Enter

  wait_for_guest_state "controlled target completes the input sequence" 10 ssh_session \
    "test -f /tmp/tablet-input.hex" || {
      ssh_session "printf 'active window: '; hyprctl -j activewindow | jq -c '{address,class,title}'; \
        printf 'tablet status: '; omarchy-shell tablet-mode status; \
        printf 'target log: '; cat /tmp/tablet-target.log 2>/dev/null || true"
      return 1
    }
  ssh_session "printf 'received input hex: '; cat /tmp/tablet-input.hex" || return 1
  ssh_session "grep -qx '614221201b5b447f1b5b43091b031b780d' /tmp/tablet-input.hex" || return 1
  printf 'ok - terminal control receives exact keys, named Space, and Ctrl/Alt chords\n'
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  ssh_session "omarchy-shell tablet-mode status | jq -e '.shift == false and ([.modifiers[]] | any) == false and .backend == \"ready\" and .busy == false'" || return 1

  log "Proving named Space, chords, navigation and rapid taps in real Chromium"
  ssh_session "hyprctl eval 'hl.dispatch(hl.dsp.window.close({ window = \"address:$target_address\" }))' >/dev/null; \
    rm -f /tmp/tablet-chromium-result /tmp/tablet-chromium-server.pid; \
    python ${remote_fixture_dir}/chromium-input-target.py /tmp/tablet-chromium-result \
      >/tmp/tablet-chromium-server.log 2>&1 & echo \$! >/tmp/tablet-chromium-server.pid; \
    chromium --ozone-platform=wayland --user-data-dir=/tmp/tablet-chromium-profile \
      --no-first-run --no-default-browser-check --disable-sync --disable-extensions \
      --app=http://127.0.0.1:18473/ >/tmp/tablet-chromium.log 2>&1 &" || return 1
  wait_for_guest_state "Chromium textarea has focus while the keyboard remains visible" 25 ssh_session \
    "hyprctl -j activewindow | jq -e '.title == \"Tablet Chromium Input\"' && \
     omarchy-shell tablet-mode status | jq -e '.visible == true'" || return 1
  target_address=$(ssh_session "hyprctl -j activewindow | jq -r '.address'") || return 1
  tap_at 1280 800 123 659 || return 1      # a
  tap_at 1280 800 682 767 || return 1      # named Space
  tap_at 1280 800 540 715 || return 1      # b
  wait_for_guest_state "Chromium receives Space between printable keys" 10 ssh_session \
    "test \"\$(cat /tmp/tablet-chromium-result 2>/dev/null)\" = 'a b'" || return 1
  long_press_at 1280 800 915 659 || return 1 # Semicolon opens Colon
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  capture_console "success-tablet-04a-chromium-long-press"
  tap_at 1280 800 915 608 || return 1      # Colon alternative
  wait_for_guest_state "Chromium receives the exact developer alternative" 10 ssh_session \
    "test \"\$(cat /tmp/tablet-chromium-result 2>/dev/null)\" = 'a b:' && \
     omarchy-shell tablet-mode status | jq -e '.alternatesVisible == false'" || return 1
  tap_at 1280 800 150 767 || return 1      # Ctrl
  tap_at 1280 800 123 659 || return 1      # Ctrl+A
  tap_at 1280 800 125 710 || return 1      # Shift
  tap_at 1280 800 540 715 || return 1      # Shift+B
  tap_at 1280 800 215 608 0.01 || return 1 # rapid q
  tap_at 1280 800 215 608 0.01 || return 1 # rapid q
  tap_at 1280 800 215 608 0.01 || return 1 # rapid q
  tap_at 1280 800 682 767 || return 1      # Space
  tap_at 1280 800 1050 767 || return 1     # Left
  tap_at 1280 800 1210 557 || return 1     # Backspace
  tap_at 1280 800 1220 767 || return 1     # Right
  tap_at 1280 800 1128 659 || return 1     # Enter
  wait_for_guest_state "Chromium receives the exact rapid/chord sequence" 15 ssh_session \
    "test \"\$(od -An -tx1 /tmp/tablet-chromium-result | tr -d ' \n')\" = '427171200a'" || return 1
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address' && \
    omarchy-shell tablet-mode status | jq -e '.busy == false and ([.modifiers[]] | any) == false'" || return 1
  capture_console "success-tablet-04-chromium-input-1280x800"

  log "Proving named Space, Ctrl/Shift chords, navigation and Enter in GTK"
  ssh_session "hyprctl eval 'hl.dispatch(hl.dsp.window.close({ window = \"address:$target_address\" }))' >/dev/null; \
    kill \"\$(cat /tmp/tablet-chromium-server.pid)\"; \
    rm -f /tmp/tablet-gtk-result /tmp/tablet-gtk-activated; \
    /tmp/omarchy-tablet-gtk-target /tmp/tablet-gtk-result /tmp/tablet-gtk-activated \
      >/tmp/tablet-gtk.log 2>&1 &" || return 1
  wait_for_guest_state "GTK entry has focus while the keyboard remains visible" 20 ssh_session \
    "hyprctl -j activewindow | jq -e '.title == \"Tablet GTK Input\"' && \
     omarchy-shell tablet-mode status | jq -e '.visible == true'" || return 1
  target_address=$(ssh_session "hyprctl -j activewindow | jq -r '.address'") || return 1
  tap_at 1280 800 123 659 || return 1      # a
  tap_at 1280 800 682 767 || return 1      # named Space
  tap_at 1280 800 540 715 || return 1      # b
  wait_for_guest_state "GTK receives Space between printable keys" 10 ssh_session \
    "test \"\$(cat /tmp/tablet-gtk-result 2>/dev/null)\" = 'a b'" || return 1
  long_press_at 1280 800 941 715 || return 1 # Slash opens Question
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  tap_at 1280 800 941 664 || return 1      # Question alternative
  wait_for_guest_state "GTK receives the exact developer alternative" 10 ssh_session \
    "test \"\$(cat /tmp/tablet-gtk-result 2>/dev/null)\" = 'a b?' && \
     omarchy-shell tablet-mode status | jq -e '.alternatesVisible == false'" || return 1
  tap_at 1280 800 150 767 || return 1      # Ctrl
  tap_at 1280 800 123 659 || return 1      # Ctrl+A
  tap_at 1280 800 125 710 || return 1      # Shift
  tap_at 1280 800 410 715 || return 1      # Shift+C
  tap_at 1280 800 306 659 0.01 || return 1 # rapid d
  tap_at 1280 800 306 659 0.01 || return 1 # rapid d
  tap_at 1280 800 306 659 0.01 || return 1 # rapid d
  tap_at 1280 800 306 659 0.01 || return 1 # rapid d
  tap_at 1280 800 1050 767 || return 1     # Left
  tap_at 1280 800 1210 557 || return 1     # Backspace
  tap_at 1280 800 1128 659 || return 1     # Enter
  wait_for_guest_state "GTK receives the exact rapid/chord sequence and activation" 15 ssh_session \
    "test \"\$(cat /tmp/tablet-gtk-result 2>/dev/null)\" = 'Cddd' && \
     grep -qx activated /tmp/tablet-gtk-activated" || return 1
  ssh_session "test \"\$(hyprctl -j activewindow | jq -r '.address')\" = '$target_address'" || return 1
  capture_console "success-tablet-05-gtk-input-1280x800"

  log "Proving backend failure clears one-shot state and pending actions"
  ssh_session "touch /tmp/omarchy-tablet-wtype-fail" || return 1
  tap_at 1280 800 150 767 0.01 || return 1 # Ctrl
  tap_at 1280 800 123 659 0.01 || return 1 # failing Ctrl+A
  wait_for_guest_state "backend failure is contained without a stuck modifier" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.backend == \"backend-error\" and .busy == false and ([.modifiers[]] | any) == false' && \
     test \"\$(cat /tmp/tablet-gtk-result)\" = 'Cddd' && ! pgrep -u \"\$(id -u)\" -x wtype >/dev/null" || return 1
  prove_physical_super_space "backend failure" || return 1
  ssh_session "rm -f /tmp/omarchy-tablet-wtype-fail" || return 1

  log "Proving hide terminates a live held-modifier backend and releases Ctrl"
  ssh_session "touch /tmp/omarchy-tablet-wtype-hold" || return 1
  tap_at 1280 800 150 767 0.01 || return 1 # Ctrl
  tap_at 1280 800 123 659 0.01 || return 1 # backend holds Ctrl
  wait_for_guest_state "held modifier backend is active" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.busy == true' && pgrep -u \"\$(id -u)\" -x wtype >/dev/null" || return 1
  ssh_session "omarchy-shell tablet-mode hide | grep -qx ok" || return 1
  wait_for_guest_state "hide cancels the backend and clears all modifier state" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.visible == false and .busy == false and ([.modifiers[]] | any) == false' && \
     ! pgrep -u \"\$(id -u)\" -x wtype >/dev/null" || return 1
  ssh_session "rm -f /tmp/omarchy-tablet-wtype-hold; /usr/bin/wtype x" || return 1
  wait_for_guest_state "post-hide input proves Ctrl is not stuck" 10 ssh_session \
    "test \"\$(cat /tmp/tablet-gtk-result)\" = 'Cddxd'" || return 1
  prove_physical_super_space "hide and held-backend destruction" || return 1

  ssh_session "omarchy-shell tablet-mode hide | grep -qx ok" || return 1
  wait_for_guest_state "hide removes the keyboard layer" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"off\" and .visible == false' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 0'" || return 1

  log "Checking the 1920x1200 reference 16:10 viewport"
  ssh_session 'monitor=$(hyprctl -j monitors | jq -r ".[0].name"); hyprctl eval "hl.monitor({ output = \"$monitor\", mode = \"1920x1200@60\", position = \"0x0\", scale = 1 })" >/dev/null' || return 1
  wait_for_guest_state "reference 16:10 viewport is active" 15 ssh_session \
    "hyprctl -j monitors | jq -e '.[0].width == 1920 and .[0].height == 1200'" || return 1
  capture_console "success-tablet-04-hidden-1920x1200"
  ssh_session "omarchy-shell tablet-mode show | grep -qx ok" || return 1
  wait_for_guest_state "keyboard appears at reference viewport" 10 ssh_session \
    "hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 1'" || return 1
  capture_console "success-tablet-05-visible-1920x1200"
  tap_at 1920 1200 445 1112 || return 1
  wait_for_guest_state "Shift appears at reference viewport" 5 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.shift == true'" || return 1
  capture_console "success-tablet-06-shift-1920x1200"
  tap_at 1920 1200 445 1112 || return 1
  ssh_session "printf '%s\n' '{\"switches\":[{\"name\":\"Asus WMI hotkeys\"}],\"keyboards\":[{\"name\":\"at-translated-set-2-keyboard\"},{\"name\":\"asustek-computer-inc.-n-key-device\"}]}' \
      > /tmp/omarchy-tablet-detector-devices.json; \
    omarchy-shell tablet-mode hide >/dev/null; omarchy-shell tablet-mode mode auto >/dev/null" || return 1
  wait_for_guest_state "Auto is hidden again after the typing keyboard reattaches" 10 ssh_session \
    "omarchy-shell tablet-mode status | jq -e '.mode == \"auto\" and .detector.active == false and .visible == false'" || return 1

  log "Checking the Z13 fractional-scale geometry regression"
  ssh_session 'monitor=$(hyprctl -j monitors | jq -r ".[0].name"); hyprctl eval "hl.monitor({ output = \"$monitor\", mode = \"1920x1200@60\", position = \"0x0\", scale = 1.6 })" >/dev/null' || return 1
  wait_for_guest_state "1.6 fractional monitor scale is active" 15 ssh_session \
    "hyprctl -j monitors | jq -e '.[0].scale == 1.6'" || return 1
  ssh_session "omarchy-shell tablet-mode mode on >/dev/null" || return 1
  wait_for_guest_state "scaled keyboard layer and client edges converge" 15 ssh_session \
    "client_bottom=\$(hyprctl -j activewindow | jq '.at[1] + .size[1]'); \
     keyboard_top=\$(hyprctl -j layers | jq '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | first | (.y // .geometry[1])'); \
     delta=\$((client_bottom - keyboard_top)); \
     test \"\$delta\" -ge -2 && test \"\$delta\" -le 2" || return 1
  capture_console "success-tablet-06b-visible-1920x1200-scale1.6"
  ssh_session "omarchy-shell tablet-mode hide >/dev/null" || return 1

  log "Proving disable, rescan, re-enable and removal cleanup"
  ssh_guest "git -C ${remote_plugin_dir} -c user.name='Tablet gate' -c user.email='tablet-gate.invalid' \
    commit --allow-empty -m 'Disposable update fixture' >/dev/null" || return 1
  ssh_session "omarchy plugin update dev.omarchy.tablet-mode --yes" || return 1
  wait_for_guest_state "plugin update reloads current service and widget identities" 20 ssh_session \
    "TABLET_PLUGIN_ROOT=${remote_plugin_dir} ${remote_fixture_dir}/verify-live-update" || return 1
  prove_physical_super_space "service update and reload" || return 1
  ssh_session "omarchy-plugin-disable dev.omarchy.tablet-mode" || return 1
  wait_for_guest_state "disable unloads service, widget and keyboard layer" 15 ssh_session \
    "omarchy-plugin-list --json | jq -e 'any(.[]; .id == \"dev.omarchy.tablet-mode\" and .enabled == false)' && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 0' && \
     ! omarchy-shell tablet-mode status >/dev/null 2>&1" || return 1
  prove_physical_super_space "plugin disable" || return 1
  ssh_session "omarchy-shell shell rescanPlugins; \
    omarchy-plugin-list --json | jq -e 'any(.[]; .id == \"dev.omarchy.tablet-mode\" and .enabled == false)'" || return 1
  ssh_session "omarchy-plugin-enable dev.omarchy.tablet-mode" || return 1
  wait_for_guest_state "plugin re-enables after rescan" 15 ssh_session \
    "omarchy-shell tablet-mode mode on >/dev/null && \
     omarchy-shell tablet-mode status | jq -e '.visible == true'" || return 1
  ssh_session "omarchy-plugin-disable dev.omarchy.tablet-mode; omarchy-plugin-remove dev.omarchy.tablet-mode --yes" || return 1
  wait_for_guest_state "removal leaves no plugin config, process or layer residue" 20 ssh_session \
    "test ! -e \"\$HOME/.config/omarchy/plugins/dev.omarchy.tablet-mode\" && \
     omarchy-plugin-list --json | jq -e 'all(.[]; .id != \"dev.omarchy.tablet-mode\")' && \
     jq -e '[.. | objects | .id? // empty] | all(. != \"dev.omarchy.tablet-mode\")' \"\$HOME/.config/omarchy/shell.json\" && \
     hyprctl -j layers | jq -e '[.. | objects | select(.namespace? == \"omarchy-tablet-keyboard\")] | length == 0' && \
     ! pgrep -u \"\$(id -u)\" -x wtype >/dev/null && \
     ! omarchy-shell tablet-mode status >/dev/null 2>&1" || return 1
  prove_physical_super_space "plugin removal" || return 1
  ssh_session "test -z \"\$(hyprctl configerrors)\"" || return 1
  ssh_session "printf 'Expected XKB option recompilation warnings during wtype lifecycle: '; \
    journalctl --user -b --no-pager 2>/dev/null | grep -c 'Key <LFSH> added to map for multiple modifiers' || true" || return 1
  ssh_guest "echo '$GUEST_PASSWORD' | sudo -S rm -f /usr/local/bin/hyprctl /usr/local/bin/wtype" || return 1
  ssh_session "rm -f /tmp/omarchy-tablet-detector-devices.json /tmp/omarchy-tablet-wtype-fail \
    /tmp/omarchy-tablet-wtype-hold" || return 1
  capture_console "success-tablet-07-removed"

  printf 'ok - tablet mode lifecycle, pointer typing, focus and cleanup passed\n'
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omarchy_host_test "$@"
fi
