#!/usr/bin/env bash
set -Eeuo pipefail
: "${ANDROID_HOME:?ANDROID_HOME is required}"
: "${APK_PATH:?APK_PATH is required}"
: "${EXPECTED_PACKAGE:?EXPECTED_PACKAGE is required}"
: "${SCREENSHOT_PYTHON:?SCREENSHOT_PYTHON is required}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVIDENCE_DIR="${EVIDENCE_DIR:-evidence}"
AVD_NAME="${ANDROID_AVD_NAME:-android-nav-api35}"
EMULATOR_PORT="${EMULATOR_PORT:-5554}"
ANDROID_SERIAL="emulator-${EMULATOR_PORT}"
: "${ANDROID_EMULATOR_ACCEL:?ANDROID_EMULATOR_ACCEL must be set by the KVM detection step}"
EMULATOR_ACCEL_MODE="$ANDROID_EMULATOR_ACCEL"
case "$EMULATOR_ACCEL_MODE" in
  on|off) ;;
  *) echo "::error::ANDROID_EMULATOR_ACCEL must be 'on' or 'off'." >&2; exit 64 ;;
esac
BOOT_TIMEOUT_SECONDS="${ANDROID_BOOT_TIMEOUT_SECONDS:-900}"
SERVICE_TIMEOUT_SECONDS="${ANDROID_SERVICE_TIMEOUT_SECONDS:-120}"
ADB_BIN="$ANDROID_HOME/platform-tools/adb"
EMULATOR_BIN="$ANDROID_HOME/emulator/emulator"
READINESS_HELPER="$SCRIPT_DIR/wait-for-android-readiness.sh"
EMULATOR_PID=""
for required in "$ADB_BIN" "$EMULATOR_BIN"; do
  [[ -x "$required" ]] || { echo "::error::Required executable not found: $required" >&2; exit 1; }
done
# This helper is invoked through Bash, so it needs to be a readable file,
# not an executable file. Repository scripts are intentionally mode 100644.
[[ -f "$READINESS_HELPER" && -r "$READINESS_HELPER" ]] || {
  echo "::error::Required Bash script not found or unreadable: $READINESS_HELPER" >&2
  exit 1
}
mkdir -p "$EVIDENCE_DIR/diagnostics"
printf 'VM acceleration mode: %s\n' "$EMULATOR_ACCEL_MODE" > "$EVIDENCE_DIR/diagnostics/emulator-acceleration.txt"
if [[ "$EMULATOR_ACCEL_MODE" == "on" ]]; then
  if ! "$EMULATOR_BIN" -accel-check > "$EVIDENCE_DIR/diagnostics/emulator-accel-check.txt" 2>&1; then
    echo "::error::KVM was selected but emulator -accel-check failed." >&2
    cat "$EVIDENCE_DIR/diagnostics/emulator-accel-check.txt" >&2
    exit 1
  fi
else
  echo "TCG fallback selected; software CPU emulation is significantly slower." \
    | tee "$EVIDENCE_DIR/diagnostics/emulator-accel-check.txt"
fi
export ANDROID_AVD_HOME ANDROID_SERIAL ADB_BIN
export PATH="$ANDROID_HOME/platform-tools:$PATH"
if [[ "$EMULATOR_ACCEL_MODE" == "off" ]]; then
  export ANDROID_I_WANT_MY_TCG=yes
fi
write_bootstrap_junit() {
  local failures="$1"
  local failure_xml=""
  if [[ "$failures" == "1" ]]; then failure_xml='<failure message="Android emulator bootstrap did not reach a usable framework state."/>'; fi
  {
    printf '<testsuite name="android-emulator-bootstrap" tests="1" failures="%s" errors="0" skipped="0">\n' "$failures"
    printf '  <testcase classname="android.nav.bootstrap" name="android_framework_ready">%s</testcase>\n' "$failure_xml"
    printf '</testsuite>\n'
  } > "$EVIDENCE_DIR/junit-emulator-bootstrap.xml"
}
cleanup() {
  local rc=$?
  trap - EXIT
  set +e
  if [[ -n "$EMULATOR_PID" ]] && "$ADB_BIN" -s "$ANDROID_SERIAL" get-state >/dev/null 2>&1; then
    "$ADB_BIN" -s "$ANDROID_SERIAL" logcat -d -t 12000 -b all > "$EVIDENCE_DIR/diagnostics/emulator-final-logcat.txt" 2>&1
    "$ADB_BIN" -s "$ANDROID_SERIAL" shell dumpsys activity activities > "$EVIDENCE_DIR/diagnostics/emulator-final-activities.txt" 2>&1
    "$ADB_BIN" -s "$ANDROID_SERIAL" shell service check input > "$EVIDENCE_DIR/diagnostics/emulator-final-input-service.txt" 2>&1
    "$ADB_BIN" -s "$ANDROID_SERIAL" emu kill >> "$EVIDENCE_DIR/diagnostics/emulator-shutdown.txt" 2>&1
  fi
  if [[ -n "$EMULATOR_PID" ]] && kill -0 "$EMULATOR_PID" 2>/dev/null; then kill "$EMULATOR_PID" 2>/dev/null; fi
  if [[ -n "$EMULATOR_PID" ]]; then wait "$EMULATOR_PID" 2>/dev/null; fi
  if [[ ! -s "$EVIDENCE_DIR/junit-emulator-bootstrap.xml" ]]; then
    if [[ "$rc" -eq 0 ]]; then write_bootstrap_junit 0; else write_bootstrap_junit 1; fi
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$ADB_BIN" start-server > "$EVIDENCE_DIR/diagnostics/adb-start-server.txt" 2>&1
"$EMULATOR_BIN" \
  -port "$EMULATOR_PORT" \
  -avd "$AVD_NAME" \
  -no-window \
  -gpu swiftshader_indirect \
  -no-snapshot \
  -no-audio \
  -no-boot-anim \
  -camera-back none \
  -accel "$EMULATOR_ACCEL_MODE" \
  -no-metrics \
  > "$EVIDENCE_DIR/diagnostics/emulator.log" 2>&1 &
EMULATOR_PID=$!
# sys.boot_completed does not guarantee that all framework services are registered.
ANDROID_READY_POLL_INTERVAL_SECONDS="${ANDROID_READY_POLL_INTERVAL_SECONDS:-2}" \
  bash "$READINESS_HELPER" "$ANDROID_SERIAL" "$BOOT_TIMEOUT_SECONDS" "$EVIDENCE_DIR/diagnostics/android-readiness.log"
if ! "$ADB_BIN" -s "$ANDROID_SERIAL" shell input keyevent 82 > "$EVIDENCE_DIR/diagnostics/unlock-screen.txt" 2>&1; then
  echo "Initial unlock keyevent failed; rechecking Android framework service readiness." >&2
  bash "$READINESS_HELPER" "$ANDROID_SERIAL" "$SERVICE_TIMEOUT_SECONDS" "$EVIDENCE_DIR/diagnostics/android-readiness-retry.log"
  "$ADB_BIN" -s "$ANDROID_SERIAL" shell input keyevent 82 >> "$EVIDENCE_DIR/diagnostics/unlock-screen.txt" 2>&1
fi
for setting in window_animation_scale transition_animation_scale animator_duration_scale; do
  if ! "$ADB_BIN" -s "$ANDROID_SERIAL" shell settings put global "$setting" 0.0; then
    echo "Settings update failed for $setting; waiting for provider and retrying." >&2
    bash "$READINESS_HELPER" "$ANDROID_SERIAL" "$SERVICE_TIMEOUT_SECONDS" "$EVIDENCE_DIR/diagnostics/android-readiness-settings-retry.log"
    "$ADB_BIN" -s "$ANDROID_SERIAL" shell settings put global "$setting" 0.0
  fi
done
"$ADB_BIN" -s "$ANDROID_SERIAL" logcat -c
write_bootstrap_junit 0
ENABLE_LOCATION_SCENARIOS=1 bash "$SCRIPT_DIR/emulator-smoke.sh"
bash "$SCRIPT_DIR/location-scenario.sh"
