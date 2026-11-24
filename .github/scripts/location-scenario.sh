#!/usr/bin/env bash
set -Eeuo pipefail

: "${EXPECTED_PACKAGE:?EXPECTED_PACKAGE is required}"
: "${SCREENSHOT_PYTHON:?SCREENSHOT_PYTHON is required}"

ANDROID_SERIAL="${ANDROID_SERIAL:-emulator-${EMULATOR_PORT:-5554}}"
ADB_BIN="${ADB_BIN:-adb}"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"
LAB_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="${LOCATION_MARKER_CHECKER:-$LAB_ROOT/scripts/check-location-marker.py}"
LOCATION_TIMEOUT_SECONDS="${LOCATION_SCENARIO_TIMEOUT_SECONDS:-75}"
SECOND_LONGITUDE="${SECOND_FIX_LONGITUDE:-2.3376}"
SECOND_LATITUDE="${SECOND_FIX_LATITUDE:-48.8606}"

mkdir -p "$EVIDENCE_DIR/screenshots" "$EVIDENCE_DIR/diagnostics"
checks=0
failures=0
: > "$EVIDENCE_DIR/junit-location-cases.xml"

adb_cmd() {
  "$ADB_BIN" -s "$ANDROID_SERIAL" "$@"
}

record_check() {
  local name="$1" passed="$2"
  checks=$((checks + 1))
  if [[ "$passed" == "true" ]]; then
    printf '  <testcase classname="android.nav.location" name="%s"/>\n' "$name" >> "$EVIDENCE_DIR/junit-location-cases.xml"
  else
    failures=$((failures + 1))
    printf '  <testcase classname="android.nav.location" name="%s"><failure message="Assertion failed: %s"/></testcase>\n' "$name" "$name" >> "$EVIDENCE_DIR/junit-location-cases.xml"
  fi
}

finish_location_test() {
  local rc=$?
  trap - EXIT
  set +e
  adb_cmd shell dumpsys location > "$EVIDENCE_DIR/diagnostics/location-provider-dump.txt" 2>&1
  adb_cmd shell dumpsys activity activities > "$EVIDENCE_DIR/diagnostics/location-activities.txt" 2>&1
  adb_cmd shell uiautomator dump /sdcard/location-window.xml > "$EVIDENCE_DIR/diagnostics/location-uiautomator-dump.txt" 2>&1
  adb_cmd pull /sdcard/location-window.xml "$EVIDENCE_DIR/diagnostics/location-window.xml" >> "$EVIDENCE_DIR/diagnostics/location-uiautomator-dump.txt" 2>&1
  adb_cmd logcat -d -t 8000 -b all > "$EVIDENCE_DIR/diagnostics/location-logcat.txt" 2>&1
  {
    printf '<testsuite name="android-nav-synthetic-location" tests="%s" failures="%s" errors="0" skipped="0">\n' "$checks" "$failures"
    cat "$EVIDENCE_DIR/junit-location-cases.xml"
    printf '</testsuite>\n'
  } > "$EVIDENCE_DIR/junit-location.xml"
  if [[ "$rc" -ne 0 || "$failures" -ne 0 ]]; then
    echo "::error::Synthetic location scenarios failed (script_exit=$rc, assertion_failures=$failures)."
    exit 1
  fi
  echo "Synthetic location scenarios passed: permissions, initial GPS, second fix, map pan and recenter."
}
trap finish_location_test EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

wait_for_marker() {
  local expectation="$1" screenshot="$2" output="$3" compare_to="${4:-}" deadline
  deadline=$((SECONDS + LOCATION_TIMEOUT_SECONDS))
  while (( SECONDS < deadline )); do
    if adb_cmd exec-out screencap -p > "$screenshot" 2> "$output.capture.log"; then
      local -a checker_args=("$SCREENSHOT_PYTHON" "$CHECKER" "$screenshot" --expect "$expectation")
      if [[ -n "$compare_to" ]]; then checker_args+=(--compare-to "$compare_to"); fi
      if "${checker_args[@]}" > "$output" 2>&1; then
        return 0
      fi
    fi
    sleep 2
  done
  return 1
}

# Both foreground location permissions and the initial synthetic fix were set
# before the app was started by emulator-smoke.sh.
if grep -Fq 'location_permissions=coarse,fine' "$EVIDENCE_DIR/diagnostics/location-test-fixture.txt" 2>/dev/null; then
  record_check "foreground_location_permissions_granted_before_app_launch" true
else
  record_check "foreground_location_permissions_granted_before_app_launch" false
fi

if wait_for_marker centered "$EVIDENCE_DIR/screenshots/location-initial.png" "$EVIDENCE_DIR/diagnostics/location-initial-marker-check.json"; then
  record_check "initial_synthetic_location_marker_is_centered" true
else
  record_check "initial_synthetic_location_marker_is_centered" false
fi

# Verify the second location changes the underlying map viewport while the
# location marker remains centred. This is stronger than checking geo-fix exit.
if adb_cmd emu geo fix "$SECOND_LONGITUDE" "$SECOND_LATITUDE" 35 8 0 > "$EVIDENCE_DIR/diagnostics/location-second-fix.txt" 2>&1; then
  if wait_for_marker centered "$EVIDENCE_DIR/screenshots/location-second-fix.png" "$EVIDENCE_DIR/diagnostics/location-second-marker-check.json" "$EVIDENCE_DIR/screenshots/location-initial.png"; then
    record_check "map_follow_remains_enabled_after_second_synthetic_fix" true
  else
    record_check "map_follow_remains_enabled_after_second_synthetic_fix" false
  fi
else
  record_check "map_follow_remains_enabled_after_second_synthetic_fix" false
fi

swipe_points="$("$SCREENSHOT_PYTHON" - "$EVIDENCE_DIR/screenshots/location-second-fix.png" <<'PY'
import sys
from PIL import Image
with Image.open(sys.argv[1]) as image:
    width, height = image.size
print(int(width * 0.83), int(height * 0.52), int(width * 0.35), int(height * 0.76))
PY
)" || swipe_points=""
if [[ -n "$swipe_points" ]]; then
  read -r start_x start_y end_x end_y <<< "$swipe_points"
else
  start_x=400; start_y=410; end_x=170; end_y=610
fi
if adb_cmd shell input swipe "$start_x" "$start_y" "$end_x" "$end_y" 600 > "$EVIDENCE_DIR/diagnostics/location-map-pan.txt" 2>&1 && \
   wait_for_marker off-centre "$EVIDENCE_DIR/screenshots/location-after-pan.png" "$EVIDENCE_DIR/diagnostics/location-after-pan-check.json"; then
  record_check "manual_map_pan_moves_location_marker_off_centre" true
else
  record_check "manual_map_pan_moves_location_marker_off_centre" false
fi

# Locate the recenter control through its accessibility description rather than fixed coordinates.
if adb_cmd shell uiautomator dump /sdcard/location-window.xml > "$EVIDENCE_DIR/diagnostics/recenter-control-dump.txt" 2>&1 && \
   adb_cmd pull /sdcard/location-window.xml "$EVIDENCE_DIR/diagnostics/recenter-control-window.xml" >> "$EVIDENCE_DIR/diagnostics/recenter-control-dump.txt" 2>&1; then
  tap_point="$("$SCREENSHOT_PYTHON" - "$EVIDENCE_DIR/diagnostics/recenter-control-window.xml" <<'PY'
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
try:
    root = ET.parse(Path(sys.argv[1])).getroot()
except (ET.ParseError, OSError):
    raise SystemExit(1)
for node in root.iter("node"):
    if "Use my location and recenter map" in node.attrib.get("content-desc", ""):
        match = re.fullmatch(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.attrib.get("bounds", ""))
        if match:
            left, top, right, bottom = map(int, match.groups())
            print(f"{(left + right) // 2} {(top + bottom) // 2}")
            raise SystemExit(0)
raise SystemExit(1)
PY
)" || tap_point=""
else
  tap_point=""
fi

if [[ -n "$tap_point" ]]; then
  read -r tap_x tap_y <<< "$tap_point"
  if adb_cmd shell input tap "$tap_x" "$tap_y" > "$EVIDENCE_DIR/diagnostics/location-recenter-tap.txt" 2>&1; then
    record_check "recenter_control_found_and_tapped_by_accessibility" true
    if wait_for_marker centered "$EVIDENCE_DIR/screenshots/location-after-recenter.png" "$EVIDENCE_DIR/diagnostics/location-after-recenter-check.json"; then
      record_check "recenter_returns_location_marker_to_centre" true
    else
      record_check "recenter_returns_location_marker_to_centre" false
    fi
  else
    record_check "recenter_control_found_and_tapped_by_accessibility" false
    record_check "recenter_returns_location_marker_to_centre" false
  fi
else
  record_check "recenter_control_found_and_tapped_by_accessibility" false
  record_check "recenter_returns_location_marker_to_centre" false
fi
