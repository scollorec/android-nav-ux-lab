#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/.github/scripts/emulator-smoke.sh"
CHECKER="$ROOT/scripts/check-map-screenshot.py"
PYTHON="${SCREENSHOT_PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

bash -n "$SCRIPT"
"$PYTHON" - "$CHECKER" <<'PYCODE'
from pathlib import Path
import sys
compile(Path(sys.argv[1]).read_text(), sys.argv[1], "exec")
PYCODE

mkdir -p "$TMP/bin"
"$PYTHON" - "$TMP" <<'PY'
import sys
from pathlib import Path
from PIL import Image, ImageDraw
root = Path(sys.argv[1])
blank = Image.new("RGB", (480, 800), (18, 22, 28))
blank.save(root / "blank.png")
map_image = Image.new("RGB", (480, 800), (22, 30, 40))
draw = ImageDraw.Draw(map_image)
for x in range(30, 480, 45):
    draw.line((x, 0, x - 80, 800), fill=(72, 87, 104), width=3)
for y in range(20, 800, 55):
    draw.line((0, y, 480, y + 28), fill=(107, 119, 132), width=2)
draw.rectangle((170, 260, 310, 430), fill=(31, 57, 68))
map_image.save(root / "map.png")
PY

if "$PYTHON" "$CHECKER" "$TMP/blank.png" >/dev/null 2>&1; then
  echo "Expected blank screenshot to fail" >&2
  exit 1
fi
"$PYTHON" "$CHECKER" "$TMP/map.png"

cat > "$TMP/bin/adb" <<'ADB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-s" ]]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install)
    [[ "${MOCK_FAIL_INSTALL:-0}" == "1" ]] && exit 9
    exit 0
    ;;
  shell)
    case "$2" in
      while*) exit 0 ;;
      settings) exit 0 ;;
      pm) echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys) echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}" ;;
      uiautomator) exit 0 ;;
      *) exit 0 ;;
    esac
    ;;
  pull)
    cat > "$3" <<XML
<hierarchy><node package="${EXPECTED_PACKAGE}" text="MAP READY Â· Locating you" /></hierarchy>
XML
    ;;
  exec-out) cat "$MOCK_SCREENSHOT" ;;
  logcat)
    if [[ "$2" == "-c" ]]; then exit 0; fi
    if [[ "${MOCK_CRASH:-0}" == "1" ]]; then
      echo "Process: ${EXPECTED_PACKAGE}, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi
    ;;
esac
ADB
chmod +x "$TMP/bin/adb"

export PATH="$TMP/bin:$PATH"
export EXPECTED_PACKAGE="com.example.nav"
export APK_PATH="$TMP/fake.apk"
export SCREENSHOT_PYTHON="$PYTHON"
export MOCK_SCREENSHOT="$TMP/map.png"
export MOCK_BLANK_SCREENSHOT="$TMP/blank.png"
export SMOKE_MAP_READY_TIMEOUT_SECONDS=0
export SMOKE_MAP_TILE_SETTLE_SECONDS=0
: > "$APK_PATH"

# Positive path: all seven assertions pass and JUnit is well-formed.
EVIDENCE_DIR="$TMP/success" bash "$SCRIPT"
grep -q '<testsuite name="android-nav-cloud-smoke" tests="7" failures="0"' "$TMP/success/junit-smoke.xml"
"$PYTHON" - "$TMP/success/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.tag == "testsuite" and suite.attrib["tests"] == "7" and suite.attrib["failures"] == "0"
assert len(suite.findall("testcase")) == 7
PYXML

# Missing MapLibre-ready signal must fail while preserving the generated JUnit.
# Override only the mocked UI hierarchy for this run.
cat > "$TMP/bin/adb" <<'ADB2'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-s" ]]; then shift 2; fi
case "$1" in
  wait-for-device|install|logcat) [[ "$1" == "logcat" && "$2" != "-c" ]] && exit 0 || exit 0 ;;
  shell)
    case "$2" in
      pm) echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys) echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}" ;;
    esac
    ;;
  pull) printf '<hierarchy><node package="%s" text="LOADING MAP" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3" ;;
  exec-out) cat "$MOCK_SCREENSHOT" ;;
esac
ADB2
chmod +x "$TMP/bin/adb"
if EVIDENCE_DIR="$TMP/no-map-ready" bash "$SCRIPT" > "$TMP/no-map-ready.log" 2>&1; then
  cat "$TMP/no-map-ready.log"
  echo "Expected missing MAP READY assertion to fail" >&2
  exit 1
fi
grep -q 'name="map_style_loaded"><failure' "$TMP/no-map-ready/junit-smoke.xml"
"$PYTHON" - "$TMP/no-map-ready/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "1"
assert suite.find(".//testcase[@name='map_style_loaded']/failure") is not None
PYXML

# App crash in logcat must fail even when all map checks pass.
cat > "$TMP/bin/adb" <<'ADB3'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == "-s" ]]; then shift 2; fi
case "$1" in
  wait-for-device) exit 0 ;;
  install)
    [[ "${MOCK_FAIL_INSTALL:-0}" == "1" ]] && exit 9
    exit 0
    ;;
  shell)
    case "$2" in
      pm) echo "package:/data/app/base.apk" ;;
      monkey) echo "Events injected: 1" ;;
      dumpsys)
        if [[ "${MOCK_FAIL_INSTALL:-0}" == "1" ]]; then
          echo "mResumedActivity: ActivityRecord{1 u0 com.android.launcher3/.Launcher t1}"
        else
          echo "mResumedActivity: ActivityRecord{1 u0 com.example.nav/.MainActivity t1}"
        fi
        ;;
    esac
    ;;
  pull)
    if [[ "${MOCK_FAIL_INSTALL:-0}" == "1" ]]; then
      printf '<hierarchy><node package="com.android.launcher3" text="Launcher" /></hierarchy>\n' > "$3"
    else
      printf '<hierarchy><node package="%s" text="MAP READY" /></hierarchy>\n' "$EXPECTED_PACKAGE" > "$3"
    fi
    ;;
  exec-out)
    if [[ "${MOCK_FAIL_INSTALL:-0}" == "1" ]]; then cat "$MOCK_BLANK_SCREENSHOT"; else cat "$MOCK_SCREENSHOT"; fi
    ;;
  logcat)
    if [[ "$2" != "-c" && "${MOCK_CRASH:-0}" == "1" ]]; then
      echo "Process: ${EXPECTED_PACKAGE}, PID: 123"
      echo "FATAL EXCEPTION: main"
    fi
    ;;
esac
ADB3
chmod +x "$TMP/bin/adb"
if MOCK_CRASH=1 EVIDENCE_DIR="$TMP/crash" bash "$SCRIPT" > "$TMP/crash.log 2>&1; then
  cat "$TMP/crash.log"
  echo "Expected app crash assertion to fail" >&2
  exit 1
fi
grep -q 'name="no_app_crash_or_anr"><failure' "$TMP/crash/junit-smoke.xml"
"$PYTHON" - "$TMP/crash/junit-smoke.xml" <<'PYXML'
import sys
import xml.etree.ElementTree as ET
suite = ET.parse(sys.argv[1]).getroot()
assert suite.attrib["failures"] == "1"
assert suite.find(".//testcase[@name='no_app_crash_or_anr']/failure") is not None
PYXML
ˆÈH™XYHÝ[HÚ]H›[šÈX\Ø[˜\È]\ÝÝ[˜Z[HšY]ÜÜÚXÚË‚šYˆSÐÒ×ÔÐÔ‘QS”ÒÕH‰TØ›[šËœ™ÈˆU’QSÑWÑTH‰TØ›[šË[X\ˆ˜\Ú‰ÐÔ’Tˆˆ‰TØ›[šË[X\›ÙÈˆ‰ŒNÈ[‚ˆØ]‰TØ›[šË[X\›ÙÈ‚ˆXÚÈ‘^XÝY›[šÈX\šY]ÜÜ\ÜÙ\[ÛˆÈ˜Z[ˆ‰Œ‚ˆ^]B™šB™Ü™\\H	Û˜[YOH›X\ÝšY]ÜÜÚ\×Ýš\ÝX[Ù]Z[˜Z[\™IÈ‰TØ›[šË[X\Ú[š]\Û[ÚÙKž[‚ˆ‰UÓˆˆH‰TØ›[šË[X\Ú[š]\Û[ÚÙKž[ˆ	ÔVS	Âš[\ÜÞ\Âš[\Ü[™]™YK‘[[Y[™YH\ÈUœÝZ]HHUœ\œÙJÞ\Ë˜\™Ý–ÌWJK™Ù]›ÛÝ

B˜\ÜÙ\ÝZ]K˜]šX–È™˜Z[\™\È—HOHŒH‚˜\ÜÙ\ÝZ]K™š[™
‹‹ËÝ\ÝØ\ÙVÐ˜[YOIÛX\ÝšY]ÜÜÚ\×Ýš\ÝX[Ù]Z[	×KÙ˜Z[\™HŠH\È›Ý›Û™B”VS€¢2â–ç7FÆÂf–ÇW&R×W7B7F–ÆÂG&–vvW"Wf–FVæ6R6öÆÆV7F–öâæB¥Væ—B&W÷'Bà¦–bÔô4µôd”Åô”å5DÄÃÓUd”DTä4UôD•#Ò"EDÕö–ç7FÆÂÖf–ÇW&R"&6‚"E45$•B"â"EDÕö–ç7FÆÂÖf–ÇW&RæÆör"#âc²F†Và¢6B"EDÕö–ç7FÆÂÖf–ÇW&RæÆör ¢V6†ò$W‡V7FVB–ç7FÆÆF–öâf–ÇW&RFòf–Â"âc ¢W†—B¦f§FW7B×2"EDÕö–ç7FÆÂÖf–ÇW&Rö§Væ—B×6Öö¶Rç†ÖÂ ¦w&W×væÖSÒ&µö–ç7FÆÆVB#ãÆf–ÇW&Rr"EDÕö–ç7FÆÂÖf–ÇW&Rö§Væ—B×6Öö¶Rç†ÖÂ ¢"E•D„ôâ"Ò"EDÕö–ç7FÆÂÖf–ÇW&Rö§Væ—B×6Öö¶Rç†ÖÂ"ÃÂu•„ÔÂp¦–×÷'B7—0¦–×÷'B†ÖÂæWG&VRäVÆVÖVçEG&VR2U@§7V—FRÒUBç'6R‡7—2æ&we³Ò’ævWG&ö÷B‚¦76W'B7V—FRæGG&–%²&f–ÇW&W2%ÒÓÒ#b ¦f÷"æÖR–â‚&µö–ç7FÆÆVB"Â&ÆVæ6†W%ö6öÖÖæEö6ö×ÆWFVB"Â&ö—5öf÷&Vw&÷VæB"Â'V–WFöÖF÷%÷v–æF÷uö&VÆöæw5÷Fõö"Â&Ö÷7G–ÆUöÆöFVB"Â&Ö÷f–Ww÷'Eö†5÷f—7VÅöFWF–Â"“ ¢76W'B7V—FRæf–æB†b"âò÷FW7F66U´æÖSÒw¶æÖWÒuÒöf–ÇW&R"’—2æ÷BæöæP¥•„ÔÀ ¦V6†ò$ÆÂV×VÆF÷"6Öö¶R×67&—B&Vw&W76–öâFW7G276VBâ 