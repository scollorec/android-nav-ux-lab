#!/usr/bin/env bash
set -Eeuo pipefail
if [[ $# -ne 3 ]]; then
  echo "Usage: wait-for-android-readiness.sh SERIAL TIMEOUT_SECONDS DIAGNOSTIC_LOG" >&2
  exit 64
fi
SERIAL="$1"
TIMEOUT_SECONDS="$2"
DIAGNOSTIC_LOG="$3"
ADB_BIN="${ADB_BIN:-adb}"
POLL_INTERVAL="${ANDROID_READY_POLL_INTERVAL_SECONDS:-2}"
[[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || { echo "TIMEOUT_SECONDS must be a non-negative integer" >&2; exit 64; }
[[ "$POLL_INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || { echo "ANDROID_READY_POLL_INTERVAL_SECONDS must be numeric" >&2; exit 64; }
mkdir -p "$(dirname "$DIAGNOSTIC_LOG")"
: > "$DIAGNOSTIC_LOG"
deadline=$((SECONDS + TIMEOUT_SECONDS))
last_state="not connected"
last_boot="unknown"
last_input_service="not checked"
last_settings_value="not checked"
while (( SECONDS <= deadline )); do
  last_state="$("$ADB_BIN" -s "$SERIAL" get-state 2>>"$DIAGNOSTIC_LOG" || true)"
  printf 'adb get-state: %s\n' "${last_state:-<empty>}" >> "$DIAGNOSTIC_LOG"
  if [[ "$last_state" == "device" ]]; then
    last_boot="$("$ADB_BIN" -s "$SERIAL" shell getprop sys.boot_completed 2>>"$DIAGNOSTIC_LOG" | tr -d '\r' || true)"
    printf 'sys.boot_completed: %s\n' "${last_boot:-<empty>}" >> "$DIAGNOSTIC_LOG"
    if [[ "$last_boot" == "1" ]]; then
      last_input_service="$("$ADB_BIN" -s "$SERIAL" shell service check input 2>>"$DIAGNOSTIC_LOG" || true)"
      printf 'service check input: %s\n' "${last_input_service:-<empty>}" >> "$DIAGNOSTIC_LOG"
      if [[ "$last_input_service" == *found* && "$last_input_service" != *"not found"* ]]; then
        last_settings_value="$("$ADB_BIN" -s "$SERIAL" shell settings get global window_animation_scale 2>>"$DIAGNOSTIC_LOG" || true)"
        last_settings_value="$(printf '%s' "$last_settings_value" | tr -d '\r' | tail -n 1)"
        printf 'settings get global window_animation_scale: %s\n' "${last_settings_value:-<empty>}" >> "$DIAGNOSTIC_LOG"
        if [[ "$last_settings_value" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
          echo "Android framework ready: boot complete, input service registered, Settings provider responsive."
          exit 0
        fi
      fi
    fi
  fi
  sleep "$POLL_INTERVAL"
done
{
  echo "::error::Android framework readiness timed out after ${TIMEOUT_SECONDS}s."
  echo "Last adb state: ${last_state:-<empty>}"
  echo "Last sys.boot_completed: ${last_boot:-<empty>}"
  echo "Last input service: ${last_input_service:-<empty>}"
  echo "Last settings value: ${last_settings_value:-<empty>}"
  echo "See $DIAGNOSTIC_LOG for retry diagnostics."
} >&2
exit 1
