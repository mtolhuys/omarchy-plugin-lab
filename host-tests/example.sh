#!/bin/bash

# A minimal host-driven test showing the API available to plugin scenarios.
# Production plugin tests should create their fixtures in the disposable guest,
# drive global shortcuts with press(), and assert state through ssh_session().
# Pointer-driven scenarios can source host-tests/helpers/pointer.sh and call
# qmp_pointer_tap(), followed by an assertion of the visible control's effect.

omarchy_host_test() {
  ssh_session "hyprctl -j monitors | jq -e 'length > 0'" || return 1
  ssh_session "[[ -z \$(hyprctl configerrors) ]]" || return 1
  capture_console "success-plugin-lab-host-test"
  printf 'ok - host-driven plugin lab can control the real guest session\n'
}
