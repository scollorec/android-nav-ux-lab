#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/.github/scripts/location-scenario.sh"
CHECKER="$ROOT/scripts/check-location-marker.py"
WORKFLOW="$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
LAUNCHER="$ROOT/.github/scripts/launch-emulator-and-smoke.sh"
SMOKE="$ROOT/.github/scripts/emulator-smoke.sh"
PYTHON="${SCREENSHOT_PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$SCRIPT"
"$PYTHON" -m py_compile "$CHECKER"

if [[ -f "$LAUNCHER" && -f "$SMOKE" && -f "$WORKFLOW" ]]; then
  grep -q 'bash "$SCRIPT_DIR/location-scenario.sh"' "$LAUNCHER"
  grep -q 'ENABLE_LOCATION_SCENARIOS=1' "$LAUNCHER"
  grep -q 'pm grant "$EXPECTED_PACKAGE" android.permission.ACCESS_FINE_LOCATION' "$SMOKE"
  grep -q 'emu geo fix "$INITIAL_FIX_LONGITUDE" "$INITIAL_FIX_LATITUDE"' "$SMOKE"
  grep -q 'bash tests/test-location-scenario.sh' "$WORKFLOW"
  grep -q '^  workflow_dispatch:' "$WORKFLOW"
  grep -q 'feature/uxlab-gps-location-follow-t1' "$WORKFLOW"
  if grep -Eq '^  (push|pull_request|pull_request_target):' "$WORKFLOW"; then
    echo "The workflow must remain manual-only" >&2
    exit 1
  fi
fi

"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
fixtures = (
    ("centered.png", (240, 400), (25, 30, 36)),
    ("changed.png", (240, 400), (60, 40, 30)),
    ("offcentre.png", (95, 610), (25, 30, 36)),
    ("missing.png", None, (25, 30, 36)),
)
for name, center, background in fixtures:
    image = Image.new("RGB", (480, 800), background)
    if center:
        x, y = center
        ImageDraw.Draw(image).polygon([(x, y-20), (x+11, y+13), (x, y+6), (x-11, y+13)], fill=(239, 72, 52))
    image.save(root / name)
PY

"$PYTHON" "$CHECKER" "$TMP/centered.png" --expect centered >/dev/null
"$PYTHON" "$CHECKER" "$TMP/changed.png" --expect centered --compare-to "$TMP/centered.png" >/dev/null
"$PYTHON" "$CHECKER" "$TMP/offcentre.png" --expect off-centre >/dev/null
if "$PYTHON" "$CHECKER" "$TMP/centered.png" --expect centered --compare-to "$TMP/centered.png" >/dev/null 2>&1; then
  echo "Expected unchanged map background to fail" >&2
  exit 1
fi
if "$PYTHON" "$CHECKER" "$TMP/missing.png" --expect centered >/dev/null 2>&1; then
  echo "Expected missing marker image to fail" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-s" ]]; then shift 2; fi
STATE_FILE="$MOCK_STATE_FILE"
case "${1:-}" in
  emu)
    [[ "${2:-}" == "geo" && "${3:-}" == "fix" ]] || exit 9
    printf '%s %s\n' "${4:-}" "${5:-}" >> "$MOCK_GEO_LOG"
    printf 'moved\n' > "$STATE_FILE"
    exit 0
    ;;
  shell)
    case "${2:-}" in
      input)
        case "${3:-}" in
          swipe) printf 'offcentre\n' > "$STATE_FILE" ;;
          tap) printf 'centered\n' > "$STATE_FILE" ;;
        esac
        ;;
      uiautomator) exit 0 ;;
      dumpsys) echo "Mock dumpsys location" ;;
    esac
    exit 0
    ;;
  pull)
    printf '<hierarchy><node package="%s" content-desc="Use my location and recenter map" bounds="[400,80][456,136]" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    exit 0
    ;;
  exec-out)
    case "$(cat "$STATE_FILE")" in
      offcentre) cat "$MOCK_OFFCENTRE_SCREENSHOT" ;;
      moved) cat "$MOCK_CHANGED_SCREENSHOT" ;;
      *) cat "$MOCK_CENTERED_SCREENSHOT" ;;
    esac
    exit 0
    ;;
  logcat) exit 0 ;;
esac
ADB
chmod +x "$TMP/bin/adb"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
fixtures = (
    ("centre.png", (240, 400), (25, 30, 36)),
    ("changed-screen.png", (240, 400), (60, 40, 30)),
    ("offcentre.png", (95, 610), (25, 30, 36)),
)
for name, centre, background in fixtures:
    image = Image.new("RGB", (480, 800), background)
    x, y = centre
    ImageDraw.Draw(image).polygon([(x, y-20), (x+11, y+13), (x, y+6), (x-11, y+13)], fill=(239, 72, 52))
    image.save(root / name)
PY

export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export ANDROID_SERIAL="emulator-5554"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_STATE_FILE="$TMP/state"
export MOCK_GEO_LOG="$TMP/geo.log"
export MOCK_CENTERED_SCREENSHOT="$TMP/centre.png"
export MOCK_OFFCENTRE_SCREENSHOT="$TMP/offcentre.png"
export MOCK_CHANGED_SCREENSHOT="$TMP/changed-screen.png"
printf 'centered\n' > "$MOCK_STATE_FILE"
mkdir -p "$TMP/evidence/diagnostics"
printf 'location_permissions=coarse,fine\n' > "$TMP/evidence/diagnostics/location-test-fixture.txt"
EVIDENCE_DIR="$TMP/evidence" LOCATION_SCENARIO_TIMEOUT_SECONDS=2 bash "$SCRIPT"
"$PYTHON" - "$TMP/evidence/junit-location.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
expected = {
    "foreground_location_permissions_granted_before_app_launch",
    "initial_synthetic_location_marker_is_centered",
    "map_follow_remains_enabled_after_second_synthetic_fix",
    "manual_map_pan_moves_location_marker_off_centre",
    "recenter_control_found_and_tapped_by_accessibility",
    "recenter_returns_location_marker_to_centre",
}
actual = {node.attrib["name"] for node in suite.findall("testcase")}
assert suite.attrib["tests"] == "7", suite.attrib
assert suite.attrib["failures"] == "0", suite.attrib
assert actual == expected, actual
PYXML

grep -q '2.3376 48.8606' "$MOCK_GEO_LOG"
echo "All synthetic location scenario regression tests passed."
