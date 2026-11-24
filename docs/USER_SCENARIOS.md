# Android-Nav user-scenario catalogue

**Last reviewed:** 2026-11-24  
**Application under test:** private `scollorec/Android-nav`  
**Harness:** this repository; public test infrastructure only

This catalogue is the user-journey coverage contract for the UX Lab. It is deliberately broader than the current smoke test. A scenario is not considered automated or passed merely because it is listed here.

## Evidence status

| Status | Meaning |
|---|---|
| **VERIFIED** | A hosted emulator run has executed the stated assertion and retained evidence. |
| **PARTIAL** | Some part of the journey is automated, but an important behaviour is not asserted. |
| **IMPLEMENTED-UNVERIFIED** | Harness assertions and local regression fixtures are implemented on a proposed branch, but no hosted emulator run has validated them yet. |
| **PLANNED** | The scenario is defined but not yet automated. |
| **DEPENDENCY-GATED** | The scenario needs an external service; service availability must be reported separately from app behaviour. |
| **DEVICE-ONLY** | A cloud emulator is insufficient; the named physical device or head-unit environment is required. |
| **NOT IN CURRENT POC** | The product capability is not implemented in the APK baseline being tested. |

The current hosted baseline is UX Lab run [#12](https://github.com/scollorec/android-nav-ux-lab/actions/runs/45369689487), using Android-nav source run [#173](https://github.com/scollorec/Android-nav/actions/runs/44998552450), source commit `31dbb27aa81cc37b889a01610aab3db23aecc560`. The baseline proves APK validation, emulator boot/readiness, installation, launcher completion, app foreground, MapLibre accessibility-node presence, a viewport visual heuristic and no detected crash/ANR. It does not prove GPS, map camera correctness, search, routing or navigation.

## A. Launch, permissions and lifecycle

| ID | User journey | Expected result | Execution | Status |
|---|---|---|---|---|
| APP-01 | Cold launch the app | Explore/map screen becomes interactive; no crash or ANR | Cloud UI | **PARTIAL** — run #12 verifies foreground and MapLibre surface, not full interactivity |
| APP-02 | Send app to background and return | App resumes without losing or corrupting the current screen/session | Cloud UI | PLANNED |
| APP-03 | Force-stop and relaunch | App starts cleanly and restores only the state the product intends to persist | Cloud UI | PLANNED |
| APP-04 | Rotate or change supported window size | Layout remains usable; no crash, overlap or inaccessible controls | Cloud UI | PLANNED |
| PERM-01 | Tap location control and deny permission | App remains usable and explains that location is unavailable/permission is required | Cloud UI | PLANNED |
| PERM-02 | Grant foreground location permission | App obtains a fix and enables location-dependent behaviour | Cloud UI + synthetic GPS | PLANNED |
| PERM-03 | Revoke location permission in Android settings and resume | Location use stops safely; app communicates the missing permission and does not crash | Cloud UI | PLANNED |

## B. Map and location

| ID | User journey | Expected result | Execution | Status |
|---|---|---|---|---|
| MAP-01 | Open the map | MapLibre surface is present and the viewport contains visible detail | Cloud UI + screenshot | **PARTIAL** — run #12 verifies surface and a visual heuristic only |
| LOC-01 | Launch with a synthetic location far from the demo camera | Camera and location marker move to the injected coordinate | Emulator GPS + visual marker assertion | **IMPLEMENTED-UNVERIFIED** |
| LOC-02 | Move the synthetic device location | Location marker follows the new coordinate and the map viewport changes | Emulator GPS + screenshot assertion | **IMPLEMENTED-UNVERIFIED** |
| LOC-03 | Pan the map, then tap “Use my location and recenter map” | Marker moves off-centre after pan and returns to centre after the accessible recenter control is tapped | Cloud UI + emulator GPS + screenshot assertion | **IMPLEMENTED-UNVERIFIED** |
| LOC-04 | Disable or withhold location | App presents a clear unavailable state; no stale fix is presented as current | Cloud UI + location controls | PLANNED |
| LOC-05 | Provide an old or inaccurate fix | App distinguishes stale/low-quality location from a fresh usable fix | Synthetic provider/instrumented seam | PLANNED |
| LOC-06 | Lose and regain location updates | Marker and camera recover without duplicate listeners or a crash | Emulator GPS | PLANNED |

The current MapLibre screenshot check is a rendering heuristic, not map recognition. GPS correctness must be asserted independently. A successful `emu geo fix` command alone proves only that the emulator accepted a coordinate; it does not prove that the app consumed it or rendered the marker at that position.

## C. Destination search and saved places

| ID | User journey | Expected result | Execution | Status |
|---|---|---|---|---|
| SRCH-01 | Enter a valid address, postcode or place | Relevant results appear; typing is debounced and stale responses do not replace newer results | Cloud UI + Photon | DEPENDENCY-GATED |
| SRCH-02 | Enter a query with no matches | Explicit no-results state; no invented place | Cloud UI + Photon fixture | PLANNED |
| SRCH-03 | Search while offline or when geocoding fails | Explicit service/offline state; existing UI remains usable | Network fault + UI | PLANNED |
| SRCH-04 | Select a search result | Correct place is selected and destination preview appears | Cloud UI | PLANNED |
| SRCH-05 | Reopen search and choose a recent destination | Recent destination is displayed and selectable | Cloud UI + app data persistence | PLANNED |
| SRCH-06 | Save/remove a favourite | Favourite state and label update and persist after restart | Cloud UI + app data persistence | PLANNED |
| SRCH-07 | Set and use Home/Work shortcuts | Selected saved place opens as the destination; missing shortcut has an explicit empty state | Cloud UI + app data persistence | PLANNED |

Photon is a public prototype dependency in the current app code. Deterministic UI tests should use controlled responses where possible; tests against the public endpoint must be separately labelled as integration tests.

## D. Route planning

| ID | User journey | Expected result | Execution | Status |
|---|---|---|---|---|
| ROUTE-01 | Select a destination from search | Route preview uses the intended origin and destination | Cloud UI + synthetic GPS + routing fixture | PLANNED |
| ROUTE-02 | Tap a point on the map | A destination preview and route are produced for the selected point | Cloud UI + routing fixture | PLANNED |
| ROUTE-03 | Open route choices and select an alternative | Selected route geometry and summary update together | Cloud UI + routing fixture | PLANNED |
| ROUTE-04 | Request a route while offline or when routing fails | Clear error; no fabricated route; retry remains possible | Network fault + UI | PLANNED |
| ROUTE-05 | Request a route without a fresh GPS fix but with a last-known fix | Origin freshness is communicated and route behaviour follows the documented policy | Synthetic location states | PLANNED |

Valhalla is a public prototype routing dependency in the current app code. Route-service failure must not be misreported as an app UI failure or as a successful route calculation.

## E. Active navigation

| ID | User journey | Expected result | Execution | Status |
|---|---|---|---|---|
| NAV-01 | Start navigation from a valid route preview | Active guidance and trip summary appear | Cloud UI + deterministic route | PLANNED |
| NAV-02 | Advance along the route with synthetic GPS updates | Remaining distance and next manoeuvre update consistently | Emulator GPS + route fixture | PLANNED |
| NAV-03 | Move off the planned route | Off-route detection triggers bounded rerouting | Emulator GPS + route fixture | PLANNED |
| NAV-04 | Make rerouting service unavailable | Existing guidance is retained and an explicit recovery state is shown | Network fault + UI | PLANNED |
| NAV-05 | Reach the destination | Arrival state appears and navigation session stops | Emulator GPS + route fixture | PLANNED |
| NAV-06 | End navigation before arrival | Guidance panel closes and the app returns to the appropriate map state | Cloud UI | PLANNED |
| NAV-07 | Background and resume during navigation | Session recovery follows the implemented lifecycle policy; no duplicate or stale guidance | Cloud UI + synthetic GPS | PLANNED |

The emulator can validate deterministic route-progress logic using synthetic coordinates. It cannot substitute for physical-device validation of real GPS accuracy, continuous background operation, battery use or audio behaviour.

## F. Wider product journeys

| ID | User journey | Expected result | Execution | Status |
|---|---|---|---|---|
| EV-01 | Discover charging stations | Relevant stations, connector and availability information are displayed with provenance/freshness | UI + service fixtures | NOT IN CURRENT POC |
| EV-02 | Compare tariffs and charging stops | Estimates use known inputs and disclose missing/stale data; no fabricated prices | Unit + integration + UI | NOT IN CURRENT POC |
| TRIP-01 | Open, save or resume a trip | Trip list and persisted trip state behave consistently | UI + persistence | NOT IN CURRENT POC |
| AA-01 | Connect phone app to Android Auto | Supported car navigation template and map surface appear | Desktop Head Unit | DEVICE-ONLY |
| AA-02 | Disconnect/reconnect the head unit during guidance | Shared navigation session recovers safely | Desktop Head Unit + physical head unit | DEVICE-ONLY |
| AA-03 | Use car-safe destination and charging flows | Only supported driver-safe templates/actions are exposed | Desktop Head Unit + physical head unit | DEVICE-ONLY |

These rows are intentional product coverage, not claims that the current POC already implements these capabilities. Android Auto and physical head-unit scenarios must have a separate test environment and report.

## Test execution rules

1. Keep deterministic tests separate from public-service integration tests. A Photon, Valhalla or tile-provider outage is a dependency result, not automatically an app regression.
2. Use synthetic coordinates and clearly labelled synthetic destinations only. Never commit or upload personal location history, real home/work addresses or production tokens.
3. Each automated scenario must have a stable ID, explicit preconditions, observable assertions and evidence paths.
4. A scenario can be **PASS** only when its required assertions ran and passed. Use **FAIL**, **BLOCKED**, **SKIPPED** or **NOT RUN** distinctly; never count a skipped or dependency-blocked test as a pass.
5. Retain JUnit XML, a concise machine-readable summary, screenshots for visual states, relevant UI hierarchy and bounded logcat.
6. Every report must bind results to the Android-nav source commit, upstream workflow run, artifact identity, APK SHA-256, emulator/API/device profile and UX Lab workflow run.
7. Screenshots and colour/pixel checks are supplementary evidence. Prefer stable accessibility descriptions, test tags or instrumented state assertions for semantic behaviour.
8. The Galaxy S23 remains the acceptance device for physical phone behaviour. The cloud emulator is the repeatable broad UI/flow regression environment, not a replacement for device acceptance.

## Delivery order

1. **Stage 0 — harness foundation:** trusted APK/artifact identity, accelerated emulator, framework readiness, install/launch and evidence collection. Complete.
2. **Stage 1 — app lifecycle and permissions:** APP-01 to APP-04 and PERM-01 to PERM-03.
3. **Stage 2 — map and location:** MAP-01 and LOC-01 to LOC-06. First functional expansion after this catalogue.
4. **Stage 3 — search and route preview:** SRCH-01 to SRCH-07 and ROUTE-01 to ROUTE-05.
5. **Stage 4 — active navigation:** NAV-01 to NAV-07.
6. **Stage 5 — wider product coverage:** charging and trips, when those capabilities enter the app POC.
7. **Stage 6 — Android Auto:** separate Desktop Head Unit and physical head-unit test programme.
