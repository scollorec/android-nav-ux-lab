#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$ROOT/.github/scripts/wait-for-android-readiness.sh"
LAUNCHER="$ROOT/.github/scripts/launch-emulator-and-smoke.sh"
WORKFLOW="$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
bash -n "$HELPER"
bash -n "$LAUNCHER"
helper_line="$(grep -n 'bash "$READINESS_HELPER"' "$LAUNCHER" | head -n1 | cut -d: -f1)"
input_line="$(grep -n 'shell input keyevent 82' "$LAUNCHER" | head -n1 | cut -d: -f1)"
smoke_line="$(grep -n 'bash "$SCRIPT_DIR/emulator-smoke.sh"' "$LAUNCHER" | tail -n1 | cut -d: -f1)"
[[ -n "$helper_line" && -n "$input_line" && -n "$smoke_line" ]]
(( helper_line < input_line && input_line < smoke_line ))
grep -q 'service check input' "$HELPER"
grep -q 'settings get global window_animation_scale' "$HELPER"
grep -q 'ANDROID_I_WANT_MY_TCG' "$LAUNCHER"
grep -q 'bash .github/scripts/launch-emulator-and-smoke.sh' "$WORKFLOW"
# Bash-invoked repository scripts are mode 100644; only native tools need -x.
grep -Fq 'for required in "$ADB_BIN" "$EMULATOR_BIN"; do' "$LAUNCHER"
grep -Fq '[[ -f "$READINESS_HELPER" && -r "$READINESS_HELPER" ]]' "$LAUNCHER"
if grep -Fq '[[ -x "$READINESS_HELPER" ]]' "$LAUNCHER"; then
  echo "Bash-invoked readiness helper must not require its executable bit." >&2
  exit 1
fi
if grep -q 'reactivecircus/android-emulator-runner@v2' "$WORKFLOW"; then
  echo "The workflow must not rely on the action's premature post-boot ADB command." >&2
  exit 1
fi
mkdir -p "$TMP/bin" "$TMP/state"
cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$MOCK_ADB_LOG"
if [[ "$1" == "-s" ]]; then shift 2; fi
case "$1" in
  get-state) echo device ;;
  shell)
    case "$2" in
      getprop) echo 1 ;;
      service)
        count=0
        [[ -f "$MOCK_STATE/input-count" ]] && count="$(cat "$MOCK_STATE/input-count")"
        count=$((count + 1))
        echo "$count" > "$MOCK_STATE/input-count"
        if [[ "${MOCK_INPUT_NEVER:-0}" == "1" || "$count" -lt "${MOCK_INPUT_FOUND_AFTER:-1}" ]]; then echo "Service input: not found"; else echo "Service input: found"; fi ;;
      settings)
        count=0
        [[ -f "$MOCK_STATE/settings-count" ]] && count="$(cat "$MOCK_STATE/settings-count")"
        count=$((count + 1))
        echo "$count" > "$MOCK_STATE/settings-count"
        if [[ "${MOCK_SETTINGS_NEVER:-0}" == "1" || "$count" -lt "${MOCK_SETTINGS_FOUND_AFTER:-1}" ]]; then echo "cmd: Failure calling service settings: Broken pipe (32)" >&2; exit 1; fi
        echo 1 ;;
    esac ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export ADB_BIN="$TMP/bin/adb"
export MOCK_STATE="$TMP/state"
export MOCK_ADB_LOG="$TMP/adb.log"
export ANDROID_READY_POLL_INTERVAL_SECONDS=0.05
MOCK_INPUT_FOUND_AFTER=3 MOCK_SETTINGS_FOUND_AFTER=2 \
  bash "$HELPER" emulator-5554 5 "$TMP/ready.log" > "$TMP/ready.out"
grep -q 'Android framework ready' "$TMP/ready.out"
[[ "$(cat "$MOCK_STATE/input-count")" -ge 3 ]]
[[ "$(cat "$MOCK_STATE/settings-count")" -ge 2 ]]
rm -f "$MOCK_STATE/input-count" "$MOCK_STATE/settings-count"
if MOCK_INPUT_NEVER=1 MOCK_SETTINGS_NEVER=0 MOCK_SETTINGS_FOUND_AFTER=1 \
   bash "$HELPER" emulator-5554 1 "$TMP/input-timeout.log" > "$TMP/input-timeout.out" 2>&1; then
  echo "Expected input service timeout" >&2; exit 1
fi
grep -q 'Android framework readiness timed out' "$TMP/input-timeout.out"
grep -q 'Service input: not found' "$TMP/input-timeout.log"
rm -f "$MOCK_STATE/input-count" "$MOCK_STATE/settings-count"
if MOCK_INPUT_NEVER=0 MOCK_INPUT_FOUND_AFTER=1 MOCK_SETTINGS_NEVER=1 \
   bash "$HELPER" emulator-5554 1 "$TMP/settings-timeout.log" > "$TMP/settings-timeout.out" 2>&1; then
  echo "Expected Settings provider timeout" >&2; exit 1
fi
grep -q 'Android framework readiness timed out' "$TMP/settings-timeout.out"
grep -q 'Broken pipe' "$TMP/settings-timeout.log"
echo "Android emulator framework-readiness regression tests passed."
