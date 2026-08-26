#!/bin/bash

# End-to-end test for the current plugin contract. The fixture is copied only
# into the disposable guest and made into a local git repository there.

omarchy_host_test() {
  local fixture_dir
  fixture_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../fixtures/lifecycle-plugin" && pwd)"

  log "Staging the disposable lifecycle plugin"
  tar -C "$fixture_dir" -cf - . | ssh_guest \
    "rm -rf /tmp/plugin-lab-lifecycle && mkdir -p /tmp/plugin-lab-lifecycle && tar -C /tmp/plugin-lab-lifecycle -xf -"
  ssh_guest "git -C /tmp/plugin-lab-lifecycle init -q && \
    git -C /tmp/plugin-lab-lifecycle add . && \
    git -C /tmp/plugin-lab-lifecycle -c user.name=PluginLab -c user.email=lab@invalid commit -qm fixture"

  ssh_session "rm -rf \"\$HOME/.config/omarchy/plugins/lab.lifecycle\"; \
    omarchy-plugin-add /tmp/plugin-lab-lifecycle --enable --yes"

  wait_for_guest_state "plugin is installed and enabled" 15 ssh_session \
    "test -f \"\$HOME/.config/omarchy/plugins/lab.lifecycle/manifest.json\" && \
     omarchy-plugin-list --json | jq -e 'any(.[]; .id == \"lab.lifecycle\" and .enabled == true)'"
  ssh_session "jq -e 'any(.plugins[]?; .id == \"lab.lifecycle\")' \"\$HOME/.config/omarchy/shell.json\""
  capture_console "success-plugin-lifecycle-01-enabled"

  ssh_session "omarchy-plugin-disable lab.lifecycle"
  wait_for_guest_state "plugin disables without removing its files" 15 ssh_session \
    "test -f \"\$HOME/.config/omarchy/plugins/lab.lifecycle/manifest.json\" && \
     omarchy-plugin-list --json | jq -e 'any(.[]; .id == \"lab.lifecycle\" and .enabled == false)'"

  ssh_session "omarchy-plugin-enable lab.lifecycle"
  wait_for_guest_state "plugin can be enabled again" 15 ssh_session \
    "omarchy-plugin-list --json | jq -e 'any(.[]; .id == \"lab.lifecycle\" and .enabled == true)'"

  ssh_session "omarchy-plugin-remove lab.lifecycle --yes"
  wait_for_guest_state "removal unloads the plugin and deletes its git checkout" 15 ssh_session \
    "test ! -e \"\$HOME/.config/omarchy/plugins/lab.lifecycle\" && \
     omarchy-plugin-list --json | jq -e 'all(.[]; .id != \"lab.lifecycle\")'"
  ssh_session "jq -e 'all(.plugins[]?; .id != \"lab.lifecycle\")' \"\$HOME/.config/omarchy/shell.json\""
  ssh_session "test -z \"\$(hyprctl configerrors)\""
  capture_console "success-plugin-lifecycle-02-removed"

  printf 'ok - add, enable, disable, re-enable, and remove completed in the disposable desktop\n'
}
