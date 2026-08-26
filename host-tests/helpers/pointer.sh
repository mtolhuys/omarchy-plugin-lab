#!/bin/bash

# QMP absolute-pointer helpers for host-driven scenarios. The ISO harness
# provides qmp(); callers provide the active logical viewport and target point.

qmp_pointer_tap() {
  local width="$1" height="$2" x="$3" y="$4" button="${5:-left}"
  local qx qy response

  if ((width < 2 || height < 2 || x < 0 || y < 0 || x >= width || y >= height)); then
    printf 'invalid QMP pointer geometry: viewport=%sx%s point=%s,%s\n' \
      "$width" "$height" "$x" "$y" >&2
    return 2
  fi
  case "$button" in
    left|right|middle) ;;
    *) printf 'invalid QMP pointer button: %s\n' "$button" >&2; return 2 ;;
  esac

  qx=$((x * 32767 / (width - 1)))
  qy=$((y * 32767 / (height - 1)))
  response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
    {\"type\":\"abs\",\"data\":{\"axis\":\"x\",\"value\":$qx}},
    {\"type\":\"abs\",\"data\":{\"axis\":\"y\",\"value\":$qy}}
  ]}")
  grep -q '"error"' <<<"$response" && {
    printf 'QMP absolute move failed: %s\n' "$response" >&2
    return 1
  }

  sleep 0.1
  response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
    {\"type\":\"btn\",\"data\":{\"down\":true,\"button\":\"$button\"}}
  ]}")
  grep -q '"error"' <<<"$response" && {
    printf 'QMP pointer press failed: %s\n' "$response" >&2
    return 1
  }

  sleep 0.12
  response=$(qmp "\"input-send-event\", \"arguments\": {\"events\": [
    {\"type\":\"btn\",\"data\":{\"down\":false,\"button\":\"$button\"}}
  ]}")
  grep -q '"error"' <<<"$response" && {
    printf 'QMP pointer release failed: %s\n' "$response" >&2
    return 1
  }

  sleep 0.4
}
