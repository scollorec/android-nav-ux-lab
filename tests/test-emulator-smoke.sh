#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/.github/scripts/emulator-smoke.sh"
CHECKER="$ROOT/scripts/check-map-screenshot.py"
WORKFLOW="$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
PYTHON="$SCREENSHOT_PYTHON"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$SCRIPT"
"$PYTHON" - "$CHECKER" <<'PYCODE'
from pathlib import Path
import sys
compile(Path(sys.argv[1]).read_text(), sys.argv[1], "exec")
PYCODE

grep -q '^      - name: Checkout test harness repositorygrep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
if grep -Eq '^  (push|pull_request|pull_request_target):' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"; then
  echo "The workflow must remain manual-only" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
Image.new("RGB", (480, 800), (18, 22, 28)).save(root / "blank.png")
image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-s" ]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 9 || exit 0 ;;
  shell)
    case "$2" in
      while*|settings) exit 0 ;;
      pm) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 1; echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi ;;
      uiautomator) exit 0 ;;
    esac ;;
  pull)
    if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    elif [ "$MOCK_NO_MAP_READY" = "1" ]; then
      printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY · Locating you" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi ;;
  exec-out) [ "$MOCK_BLANK" = "1" ] && cat "$MOCK_BLANK_SCREENSHOT" || cat "$MOCK_SCREENSHOT" ;;
  logcat)
    [ "$2" = "-c" ] && exit 0
    if [ "$MOCK_CRASH" = "1" ]; then
      echo "Process: $EXPECTED_PACKAGE, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export MOCK_FAIL_INSTALL=0 MOCK_CRASH=0 MOCK_NO_MAP_READY=0 MOCK_BLANK=0
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is valid XML.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite"
assert suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail and produce a JUnit failure.
if MOCK_NO_MAP_READY=1 EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"

# App crash in logcat must fail.
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log" 2>&1; then
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"

# A ready style with a blank canvas must fail the visual viewport check.
if MOCK_BLANK=1 EVIDENCE_DIR="$TMP/blank-map" bash "$SCRIPT" > "$TMP/blank-map.log" 2>&1; then
  echo "Expected blank map viewport assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_viewport_has_visual_detail"><failure' "$TMP/blank-map/junit-smoke.xml"

# An install failure must still collect diagnostics and emit JUnit.
if MOCK_FAIL_INSTALL=1 MOCK_BLANK=1 EVIDENCE_DIR="$TMP/install-failure" bash "$SCRIPT" > "$TMP/install-failure.log" 2>&1; then
  echo "Expected installation failure to fail" >&2
  exit 1
fi
test -s "$TMP/install-failure/junit-smoke.xml"
grep -q 'name="apk_installed"><failure' "$TMP/install-failure/junit-smoke.xml"
"$PYTHON" - "$TMP/install-failure/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "6"
for name in ("apk_installed", "launcher_command_completed", "app_is_foreground", "uiautomator_window_belongs_to_app", "map_style_loaded", "map_viewport_has_visual_detail"):
    assert suite.find(f".//testcase[@name='{name}']/failure") is not None
PYXML

echo "All emulator smoke-script regression tests passed."
 "$WORKFLOW"
grep -q '^        uses: actions/checkout@v4grep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
if grep -Eq '^  (push|pull_request|pull_request_target):' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"; then
  echo "The workflow must remain manual-only" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
Image.new("RGB", (480, 800), (18, 22, 28)).save(root / "blank.png")
image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-s" ]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 9 || exit 0 ;;
  shell)
    case "$2" in
      while*|settings) exit 0 ;;
      pm) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 1; echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi ;;
      uiautomator) exit 0 ;;
    esac ;;
  pull)
    if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    elif [ "$MOCK_NO_MAP_READY" = "1" ]; then
      printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY · Locating you" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi ;;
  exec-out) [ "$MOCK_BLANK" = "1" ] && cat "$MOCK_BLANK_SCREENSHOT" || cat "$MOCK_SCREENSHOT" ;;
  logcat)
    [ "$2" = "-c" ] && exit 0
    if [ "$MOCK_CRASH" = "1" ]; then
      echo "Process: $EXPECTED_PACKAGE, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export MOCK_FAIL_INSTALL=0 MOCK_CRASH=0 MOCK_NO_MAP_READY=0 MOCK_BLANK=0
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is valid XML.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite"
assert suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail and produce a JUnit failure.
if MOCK_NO_MAP_READY=1 EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"

# App crash in logcat must fail.
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log" 2>&1; then
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"

# A ready style with a blank canvas must fail the visual viewport check.
if MOCK_BLANK=1 EVIDENCE_DIR="$TMP/blank-map" bash "$SCRIPT" > "$TMP/blank-map.log" 2>&1; then
  echo "Expected blank map viewport assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_viewport_has_visual_detail"><failure' "$TMP/blank-map/junit-smoke.xml"

# An install failure must still collect diagnostics and emit JUnit.
if MOCK_FAIL_INSTALL=1 MOCK_BLANK=1 EVIDENCE_DIR="$TMP/install-failure" bash "$SCRIPT" > "$TMP/install-failure.log" 2>&1; then
  echo "Expected installation failure to fail" >&2
  exit 1
fi
test -s "$TMP/install-failure/junit-smoke.xml"
grep -q 'name="apk_installed"><failure' "$TMP/install-failure/junit-smoke.xml"
"$PYTHON" - "$TMP/install-failure/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "6"
for name in ("apk_installed", "launcher_command_completed", "app_is_foreground", "uiautomator_window_belongs_to_app", "map_style_loaded", "map_viewport_has_visual_detail"):
    assert suite.find(f".//testcase[@name='{name}']/failure") is not None
PYXML

echo "All emulator smoke-script regression tests passed."
 "$WORKFLOW"
grep -q '^          ref: \${{ github.sha }}grep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
if grep -Eq '^  (push|pull_request|pull_request_target):' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"; then
  echo "The workflow must remain manual-only" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
Image.new("RGB", (480, 800), (18, 22, 28)).save(root / "blank.png")
image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-s" ]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 9 || exit 0 ;;
  shell)
    case "$2" in
      while*|settings) exit 0 ;;
      pm) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 1; echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi ;;
      uiautomator) exit 0 ;;
    esac ;;
  pull)
    if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    elif [ "$MOCK_NO_MAP_READY" = "1" ]; then
      printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY · Locating you" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi ;;
  exec-out) [ "$MOCK_BLANK" = "1" ] && cat "$MOCK_BLANK_SCREENSHOT" || cat "$MOCK_SCREENSHOT" ;;
  logcat)
    [ "$2" = "-c" ] && exit 0
    if [ "$MOCK_CRASH" = "1" ]; then
      echo "Process: $EXPECTED_PACKAGE, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export MOCK_FAIL_INSTALL=0 MOCK_CRASH=0 MOCK_NO_MAP_READY=0 MOCK_BLANK=0
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is valid XML.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite"
assert suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail and produce a JUnit failure.
if MOCK_NO_MAP_READY=1 EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"

# App crash in logcat must fail.
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log" 2>&1; then
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"

# A ready style with a blank canvas must fail the visual viewport check.
if MOCK_BLANK=1 EVIDENCE_DIR="$TMP/blank-map" bash "$SCRIPT" > "$TMP/blank-map.log" 2>&1; then
  echo "Expected blank map viewport assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_viewport_has_visual_detail"><failure' "$TMP/blank-map/junit-smoke.xml"

# An install failure must still collect diagnostics and emit JUnit.
if MOCK_FAIL_INSTALL=1 MOCK_BLANK=1 EVIDENCE_DIR="$TMP/install-failure" bash "$SCRIPT" > "$TMP/install-failure.log" 2>&1; then
  echo "Expected installation failure to fail" >&2
  exit 1
fi
test -s "$TMP/install-failure/junit-smoke.xml"
grep -q 'name="apk_installed"><failure' "$TMP/install-failure/junit-smoke.xml"
"$PYTHON" - "$TMP/install-failure/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "6"
for name in ("apk_installed", "launcher_command_completed", "app_is_foreground", "uiautomator_window_belongs_to_app", "map_style_loaded", "map_viewport_has_visual_detail"):
    assert suite.find(f".//testcase[@name='{name}']/failure") is not None
PYXML

echo "All emulator smoke-script regression tests passed."
 "$WORKFLOW"
grep -q '^          persist-credentials: falsegrep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
if grep -Eq '^  (push|pull_request|pull_request_target):' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"; then
  echo "The workflow must remain manual-only" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
Image.new("RGB", (480, 800), (18, 22, 28)).save(root / "blank.png")
image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-s" ]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 9 || exit 0 ;;
  shell)
    case "$2" in
      while*|settings) exit 0 ;;
      pm) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 1; echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi ;;
      uiautomator) exit 0 ;;
    esac ;;
  pull)
    if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    elif [ "$MOCK_NO_MAP_READY" = "1" ]; then
      printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY · Locating you" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi ;;
  exec-out) [ "$MOCK_BLANK" = "1" ] && cat "$MOCK_BLANK_SCREENSHOT" || cat "$MOCK_SCREENSHOT" ;;
  logcat)
    [ "$2" = "-c" ] && exit 0
    if [ "$MOCK_CRASH" = "1" ]; then
      echo "Process: $EXPECTED_PACKAGE, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export MOCK_FAIL_INSTALL=0 MOCK_CRASH=0 MOCK_NO_MAP_READY=0 MOCK_BLANK=0
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is valid XML.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite"
assert suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail and produce a JUnit failure.
if MOCK_NO_MAP_READY=1 EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"

# App crash in logcat must fail.
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log" 2>&1; then
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"

# A ready style with a blank canvas must fail the visual viewport check.
if MOCK_BLANK=1 EVIDENCE_DIR="$TMP/blank-map" bash "$SCRIPT" > "$TMP/blank-map.log" 2>&1; then
  echo "Expected blank map viewport assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_viewport_has_visual_detail"><failure' "$TMP/blank-map/junit-smoke.xml"

# An install failure must still collect diagnostics and emit JUnit.
if MOCK_FAIL_INSTALL=1 MOCK_BLANK=1 EVIDENCE_DIR="$TMP/install-failure" bash "$SCRIPT" > "$TMP/install-failure.log" 2>&1; then
  echo "Expected installation failure to fail" >&2
  exit 1
fi
test -s "$TMP/install-failure/junit-smoke.xml"
grep -q 'name="apk_installed"><failure' "$TMP/install-failure/junit-smoke.xml"
"$PYTHON" - "$TMP/install-failure/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "6"
for name in ("apk_installed", "launcher_command_completed", "app_is_foreground", "uiautomator_window_belongs_to_app", "map_style_loaded", "map_viewport_has_visual_detail"):
    assert suite.find(f".//testcase[@name='{name}']/failure") is not None
PYXML

echo "All emulator smoke-script regression tests passed."
 "$WORKFLOW"
grep -q '^          script: bash .github/scripts/emulator-smoke.shgrep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
if grep -Eq '^  (push|pull_request|pull_request_target):' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"; then
  echo "The workflow must remain manual-only" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
Image.new("RGB", (480, 800), (18, 22, 28)).save(root / "blank.png")
image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-s" ]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 9 || exit 0 ;;
  shell)
    case "$2" in
      while*|settings) exit 0 ;;
      pm) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 1; echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi ;;
      uiautomator) exit 0 ;;
    esac ;;
  pull)
    if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    elif [ "$MOCK_NO_MAP_READY" = "1" ]; then
      printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY · Locating you" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi ;;
  exec-out) [ "$MOCK_BLANK" = "1" ] && cat "$MOCK_BLANK_SCREENSHOT" || cat "$MOCK_SCREENSHOT" ;;
  logcat)
    [ "$2" = "-c" ] && exit 0
    if [ "$MOCK_CRASH" = "1" ]; then
      echo "Process: $EXPECTED_PACKAGE, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export MOCK_FAIL_INSTALL=0 MOCK_CRASH=0 MOCK_NO_MAP_READY=0 MOCK_BLANK=0
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is valid XML.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite"
assert suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail and produce a JUnit failure.
if MOCK_NO_MAP_READY=1 EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"

# App crash in logcat must fail.
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log" 2>&1; then
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"

# A ready style with a blank canvas must fail the visual viewport check.
if MOCK_BLANK=1 EVIDENCE_DIR="$TMP/blank-map" bash "$SCRIPT" > "$TMP/blank-map.log" 2>&1; then
  echo "Expected blank map viewport assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_viewport_has_visual_detail"><failure' "$TMP/blank-map/junit-smoke.xml"

# An install failure must still collect diagnostics and emit JUnit.
if MOCK_FAIL_INSTALL=1 MOCK_BLANK=1 EVIDENCE_DIR="$TMP/install-failure" bash "$SCRIPT" > "$TMP/install-failure.log" 2>&1; then
  echo "Expected installation failure to fail" >&2
  exit 1
fi
test -s "$TMP/install-failure/junit-smoke.xml"
grep -q 'name="apk_installed"><failure' "$TMP/install-failure/junit-smoke.xml"
"$PYTHON" - "$TMP/install-failure/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "6"
for name in ("apk_installed", "launcher_command_completed", "app_is_foreground", "uiautomator_window_belongs_to_app", "map_style_loaded", "map_viewport_has_visual_detail"):
    assert suite.find(f".//testcase[@name='{name}']/failure") is not None
PYXML

echo "All emulator smoke-script regression tests passed."
 "$WORKFLOW"
grep -q '^  workflow_dispatch:' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"
if grep -Eq '^  (push|pull_request|pull_request_target):' "$ROOT/.github/workflows/android-nav-emulator-smoke.yml"; then
  echo "The workflow must remain manual-only" >&2
  exit 1
fi

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
Image.new("RGB", (480, 800), (18, 22, 28)).save(root / "blank.png")
image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "-s" ]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 9 || exit 0 ;;
  shell)
    case "$2" in
      while*|settings) exit 0 ;;
      pm) [ "$MOCK_FAIL_INSTALL" = "1" ] && exit 1; echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi ;;
      uiautomator) exit 0 ;;
    esac ;;
  pull)
    if [ "$MOCK_FAIL_INSTALL" = "1" ]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    elif [ "$MOCK_NO_MAP_READY" = "1" ]; then
      printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY · Locating you" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi ;;
  exec-out) [ "$MOCK_BLANK" = "1" ] && cat "$MOCK_BLANK_SCREENSHOT" || cat "$MOCK_SCREENSHOT" ;;
  logcat)
    [ "$2" = "-c" ] && exit 0
    if [ "$MOCK_CRASH" = "1" ]; then
      echo "Process: $EXPECTED_PACKAGE, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi ;;
esac
ADB
chmod +x "$TMP/bin/adb"
export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export MOCK_FAIL_INSTALL=0 MOCK_CRASH=0 MOCK_NO_MAP_READY=0 MOCK_BLANK=0
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is valid XML.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite"
assert suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail and produce a JUnit failure.
if MOCK_NO_MAP_READY=1 EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"

# App crash in logcat must fail.
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log" 2>&1; then
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"

# A ready style with a blank canvas must fail the visual viewport check.
if MOCK_BLANK=1 EVIDENCE_DIR="$TMP/blank-map" bash "$SCRIPT" > "$TMP/blank-map.log" 2>&1; then
  echo "Expected blank map viewport assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_viewport_has_visual_detail"><failure' "$TMP/blank-map/junit-smoke.xml"

# An install failure must still collect diagnostics and emit JUnit.
if MOCK_FAIL_INSTALL=1 MOCK_BLANK=1 EVIDENCE_DIR="$TMP/install-failure" bash "$SCRIPT" > "$TMP/install-failure.log" 2>&1; then
  echo "Expected installation failure to fail" >&2
  exit 1
fi
test -s "$TMP/install-failure/junit-smoke.xml"
grep -q 'name="apk_installed"><failure' "$TMP/install-failure/junit-smoke.xml"
"$PYTHON" - "$TMP/install-failure/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "6"
for name in ("apk_installed", "launcher_command_completed", "app_is_foreground", "uiautomator_window_belongs_to_app", "map_style_loaded", "map_viewport_has_visual_detail"):
    assert suite.find(f".//testcase[@name='{name}']/failure") is not None
PYXML

echo "All emulator smoke-script regression tests passed."
