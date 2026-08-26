#!/bin/bash

# Keep even the nominally headless source suite away from the host session.
# Some runtime-smoke tests launch Quickshell and several scripts contain
# privileged code paths; the disposable guest is the correct trust boundary.

omarchy_host_test() {
  [[ -d ${OMARCHY_LAB_PKGS_SOURCE:-} ]] || {
    echo "Missing OMARCHY_LAB_PKGS_SOURCE" >&2
    return 1
  }
  [[ -d ${OMARCHY_LAB_ISO_SOURCE:-} ]] || {
    echo "Missing OMARCHY_LAB_ISO_SOURCE" >&2
    return 1
  }

  log "Syncing package and ISO sources needed by cross-repository tests"
  tar -C "$OMARCHY_LAB_PKGS_SOURCE" --exclude .git -cf - . | ssh_guest \
    "rm -rf .local/share/omarchy-pkgs && mkdir -p .local/share/omarchy-pkgs && tar -C .local/share/omarchy-pkgs -xf -"
  tar -C "$OMARCHY_LAB_ISO_SOURCE" --exclude .git --exclude release --exclude test-runs -cf - . | ssh_guest \
    "rm -rf .local/share/omarchy-iso && mkdir -p .local/share/omarchy-iso && tar -C .local/share/omarchy-iso -xf -"

  # The installed fixture has package-owned omarchy-* commands in /usr/bin.
  # Source tests must see only the checkout commands they explicitly add to
  # PATH, otherwise "missing helper" guards accidentally find the packaged
  # helper and produce a false failure.
  ssh_guest 'rm -rf /tmp/plugin-lab-system-bin && mkdir /tmp/plugin-lab-system-bin &&
    for command in /usr/bin/*; do
      name=${command##*/}
      [[ $name == omarchy || $name == omarchy-* ]] && continue
      ln -s "$command" "/tmp/plugin-lab-system-bin/$name"
    done
    # One hardware helper intentionally delegates through this packaged
    # presence probe; expose that narrow dependency without reintroducing the
    # complete installed Omarchy command set.
    ln -s /usr/bin/omarchy-cmd-present /tmp/plugin-lab-system-bin/omarchy-cmd-present'

  log "Running the complete source suite inside the disposable guest"
  if [[ -n ${OMARCHY_LAB_SOURCE_TESTS:-} ]]; then
    local quoted_tests=""
    local test_file
    for test_file in $OMARCHY_LAB_SOURCE_TESTS; do
      [[ $test_file == test/* && $test_file != *..* ]] || {
        echo "Unsafe source test path: $test_file" >&2
        return 1
      }
      printf -v quoted_tests '%s %q' "$quoted_tests" "$test_file"
    done
  else
    local quoted_tests=" ./test/all"
  fi

  ssh_guest "cd .local/share/omarchy && \
    PATH=\$HOME/.local/share/mise/shims:/usr/local/sbin:/usr/local/bin:/tmp/plugin-lab-system-bin \
    LANG=C.UTF-8 LC_ALL=C.UTF-8 \
    OMARCHY_PKGS_PATH=\$HOME/.local/share/omarchy-pkgs \
    OMARCHY_ISO_PATH=\$HOME/.local/share/omarchy-iso \
    bash -c 'set -e; for test_file in$quoted_tests; do bash \"\$test_file\"; done' </dev/null"
}
