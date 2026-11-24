#!/usr/bin/env bash
set -Eeuo pipefail

: "${EXPECTED_PACKAGE:?EXPECTED_PACKAGE is required}"
: "${APK_PATH:?APK_PATH is required}"

ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-${EMULATOR_PORT:-5554}}"
SCREENSHOT_PYTHON="${SCREENSHOT_PYTHON:-python3}"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"
MAP_READY_TIMEOUT_SECONDS="${SMOKE_MAP_READY_TIMEOUT_SECONDS:-120}"
MAP_TILE_SETTLE_SECONDS="${SMOKE_MAP_TILE_SETTLE_SECONDS:-15}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCREENSHOT_CHECKER="$SCRIPT_DIR/../../scripts/check-map-screenshot.py"

mkdir -p "$EVIDENCE_DIR/screenshots" "$EVIDENCE_DIR/diagnostics"

adb_cmd() {
  adb -s "$ANDROID_SERIAL" "$@"
}

record_check() {
  local name="$1"
  local passed="$2"
  checks=$((checks + 1))
  if [[ "$passed" == "true" ]]; then
    printf '  <testcase classname="android.nav.smoke" name="%s"/>\n' "$name" >> "$EVIDENCE_DIR/junit-cases.xml"
  else
    failures=$((failures + 1))
    printf '  <testcase classname="android.nav.smoke" name="%s"><failure message="Assertion failed: %s"/></testcase>\n' "$name" "$name" >> "$EVIDENCE_DIR/junit-cases.xml"
  fi
}

finish_smoke_test() {
  local script_exit=$?
  trap - EXIT
  set +e

  # Evidence collection is best-effort and must not hide the original failure.
  adb_cmd shell dumpsys activity activities > "$EVIDENCE_DIR/activities.txt" 2>&1
  grep -E 'mResumedActivity|topResumedActivity' "$EVIDENCE_DIR/activities.txt" > "$EVIDENCE_DIR/diagnostics/resumed-activity.txt" 2>/dev/null
  adb_cmd shell uiautomator dump /sdcard/window.xml > "$EVIDENCE_DIR/diagnostics/uiautomator-dump.txt" 2>&1
  adb_cmd pull /sdcard/window.xml "$EVIDENCE_DIR/window.xml" >> "$EVIDENCE_DIR/diagnostics/uiautomator-dump.txt" 2>&1
  adb_cmd exec-out screencap -p > "$EVIDENCE_DIR/screenshots/launch.png" 2> "$EVIDENCE_DIR/diagnostics/screenshot-capture.txt"
  adb_cmd logcat -d -t 12000 -b all > "$EVIDENCE_DIR/logcat.txt" 2>&1

  checks=0
  failures=0
  : > "$EVIDENCE_DIR/junit-cases.xml"

  if grep -q '^package:' "$EVIDENCE_DIR/diagnostics/package-path.txt" 2>/dev/null; then
    record_check "apk_installed" true
  else
    record_check "apk_installed" false
  fi

  if grep -q 'Events injected: 1' "$EVIDENCE_DIR/diagnostics/launch-command.txt" 2>/dev/null; then
    record_check "launcher_command_completed" true
  else
    record_check "launcher_command_completed" false
  fi

  if grep -E 'mResumedActivity|topResumedActivity' "$EVIDENCE_DIR/diagnostics/resumed-activity.txt" 2>/dev/null | grep -Fq "$EXPECTED_PACKAGE"; then
    record_check "app_is_foreground" true
  else
    record_check "app_is_foreground" false
  fi

  if grep -Fq "package=\"$EXPECTED_PACKAGE\"" "$EVIDENCE_DIR/window.xml" 2>/dev/null; then
    record_check "uiautomator_window_belongs_to_app" true
  else
    record_check "uiautomator_window_belongs_to_app" false
  fi

  # MainActivity's diagnostic status TextView is GONE in the normal landing UI.
  # The MapLibre MapView exposes this accessibility description; the separate
  # screenshot assertion below verifies that map pixels contain visible detail.
  if grep -Fq 'Showing a Map created with MapLibre' "$EVIDENCE_DIR/window.xml" 2>/dev/null; then
    record_check "map_surface_present" true
  else
    record_check "map_surface_present" false
  fi

  if [[ -s "$EVIDENCE_DIR/screenshots/launch.png" ]] && \
      "$SCREENSHOT_PYTHON" "$SCREENSHOT_CHECKER" "$EVIDENCE_DIR/screenshots/launch.png" \
      > "$EVIDENCE_DIR/diagnostics/map-screenshot-check.txt" 2>&1; then
    record_check "map_viewport_has_visual_detail" true
  else
    record_check "map_viewport_has_visual_detail" false
  fi

  if grep -Fq "Process: $EXPECTED_PACKAGE" "$EVIDENCE_DIR/logcat.txt" || \
     grep -Fq "ANR in $EXPECTED_PACKAGE" "$EVIDENCE_DIR/logcat.txt" || \
     grep -Fq "Force finishing activity $EXPECTED_PACKAGE" "$EVIDENCE_DIR/logcat.txt"; then
    record_check "no_app_crash_or_anr" false
  else
    record_check "no_app_crash_or_anr" true
  fi

  {
    printf '<testsuite name="android-nav-cloud-smoke" tests="%s" failures="%s" errors="0" skipped="0">\n' "$checks" "$failures"
    cat "$EVIDENCE_DIR/junit-cases.xml"
    printf '</testsuite>\n'
  } > "$EVIDENCE_DIR/junit-smoke.xml"

  if [[ "$script_exit" -ne 0 || "$failures" -ne 0 ]]; then
    echo "::error::Android-nav smoke test failed (script_exit=$script_exit, assertion_failures=$failures). See uploaded diagnostics."
    exit 1
  fi
  echo "Smoke test passed: APK installed, launcher completed, app foregrounded, MapLibre surface is present, map viewport has visible detail, and no app crash/ANR was detected."
}

trap finish_smoke_test EXIT

adb_cmd wait-for-device
adb_cmd shell 'while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 2; done'
adb_cmd shell settings put system accelerometer_rotation 0
adb_cmd logcat -c
adb_cmd install -r "$APK_PATH"

installed_path="$(adb_cmd shell pm path "$EXPECTED_PACKAGE" | tr -d '\r')"
printf '%s\n' "$installed_path" > "$EVIDENCE_DIR/diagnostics/package-path.txt"
[[ "$installed_path" == package:* ]] || {
  echo "::error::Package manager cannot find installed app" >&2
  exit 1
}

# Grant only the foreground permissions required for this synthetic-location
# test run, and inject a test coordinate before the activity starts.
if [[ "${ENABLE_LOCATION_SCENARIOS:-0}" == "1" ]]; then
  INITIAL_FIX_LONGITUDE="${INITIAL_FIX_LONGITUDE:-2.2945}"
  INITIAL_FIX_LATITUDE="${INITIAL_FIX_LATITUDE:-48.8584}"
  adb_cmd shell pm grant "$EXPECTED_PACKAGE" android.permission.ACCESS_COARSE_LOCATION \
    > "$EVIDENCE_DIR/diagnostics/location-permission-grant.txt" 2>&1
  adb_cmd shell pm grant "$EXPECTED_PACKAGE" android.permission.ACCESS_FINE_LOCATION \
    >> "$EVIDENCE_DIR/diagnostics/location-permission-grant.txt" 2>&1
  adb_cmd emu geo fix "$INITIAL_FIX_LONGITUDE" "$INITIAL_FIX_LATITUDE" 35 8 0 \
    > "$EVIDENCE_DIR/diagnostics/location-initial-fix.txt" 2>&1
  {
    echo "initial_longitude=$INITIAL_FIX_LONGITUDE"
    echo "initial_latitude=$INITIAL_FIX_LATITUDE"
    echo "location_permissions=coarse,fine"
  } > "$EVIDENCE_DIR/diagnostics/location-test-fixture.txt"
fi

adb_cmd shell monkey -p "$EXPECTED_PACKAGE" -c android.intent.category.LAUNCHER 1 \
  > "$EVIDENCE_DIR/diagnostics/launch-command.txt" 2>&1

# Wait for the MapLibre MapView accessibility node instead of assuming a
# fixed startup delay. A separate screenshot assertion checks visible map detail.
map_ready_deadline=$((SECONDS + MAP_READY_TIMEOUT_SECONDS))
while true; do
  adb_cmd shell uiautomator dump /sdcard/window.xml \
    > "$EVIDENCE_DIR/diagnostics/map-readiness-dump.txt" 2>&1 || true
  adb_cmd pull /sdcard/window.xml "$EVIDENCE_DIR/diagnostics/map-readiness-window.xml" \
    >> "$EVIDENCE_DIR/diagnostics/map-readiness-dump.txt" 2>&1 || true
  if grep -Fq 'Showing a Map created with MapLibre' "$EVIDENCE_DIR/diagnostics/map-readiness-window.xml" 2>/dev/null; then
    echo "MapLibre map surface appeared in the UI hierarchy."
    break
  fi
  if (( SECONDS >= map_ready_deadline )); then
    echo "::error::Timed out waiting for the MapLibre map surface to appear in the UI hierarchy." >&2
    exit 1
  fi
  sleep 5
done

sleep "$MAP_TILE_SETTLE_SECONDS"
