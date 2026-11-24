# UX test plan

The detailed journey contract is in [USER_SCENARIOS.md](USER_SCENARIOS.md). This file tracks delivery stages and the evidence required to advance them.

## Stage 0 — emulator and artifact plumbing

- [x] Obtain a dedicated x86_64 test APK from a trusted Android-nav CI run.
- [x] Verify the artifact's source commit and SHA-256.
- [x] Enable KVM permissions where `/dev/kvm` is available and verify `emulator -accel-check`; use TCG only as an explicit fallback.
- [x] Boot the selected x86_64 emulator image on a GitHub-hosted Linux runner with the verified acceleration mode.
- [x] Wait for `sys.boot_completed`, InputManager registration and a responsive Settings provider before input or settings operations.
- [x] Install the APK and verify the expected package is present.
- [x] Launch the main activity and capture a baseline screenshot.
- [x] Capture logcat and upload evidence even when a test fails.

**Evidence:** UX Lab [run #12](https://github.com/scollorec/android-nav-ux-lab/actions/runs/45369689487), source Android-nav [run #173](https://github.com/scollorec/Android-nav/actions/runs/44998552450). Run #12 completed successfully using KVM. Seven JUnit smoke assertions and the Android framework readiness test passed. This stage proves the harness and APK plumbing, not the full user journeys.

## Stage 1 — launch, lifecycle and permissions

- [ ] Cold launch reaches an interactive Explore/map screen (not merely a foreground activity).
- [ ] App remains stable after background / foreground.
- [ ] Force-stop and relaunch follow the intended state-restoration policy.
- [ ] Rotation or supported window-size changes do not crash or obscure controls.
- [ ] Permission-denied, permission-granted and permission-revoked states are handled.

See APP-01 to APP-04 and PERM-01 to PERM-03 in the scenario catalogue.

## Stage 2 — map and location

- [x] MapLibre MapView appears in the UI hierarchy and the captured viewport contains visible map detail; the viewport check is a visual heuristic only.
- [ ] Initial camera and user-location marker follow an injected synthetic coordinate that differs materially from the demo camera. (Harness implementation added; hosted result pending.)
- [ ] A second synthetic GPS fix moves the location marker correctly. (Harness implementation added; hosted result pending.)
- [ ] Manual map movement disables follow; the recenter control restores the camera to the injected fix. (Harness implementation added; hosted result pending.)
- [ ] Disabled, unavailable, stale and low-accuracy location states are communicated correctly.
- [ ] Location updates recover after interruption without duplicate listeners or a crash.

The existing run #12 evidence covers only MapLibre surface presence and a viewport-detail heuristic. It does not verify the initial camera, a location marker, GPS updates or re-centering.

See MAP-01 and LOC-01 to LOC-06 in the scenario catalogue.

## Stage 3 — destination search and route preview

- [ ] Search accepts address, postcode and place queries.
- [ ] Results render, stale responses do not replace newer queries and a selected result opens the correct preview.
- [ ] Recent destinations, favourites and Home/Work shortcuts persist as intended.
- [ ] Map taps create the expected destination preview.
- [ ] Route preview and alternative selection use the intended route geometry and summaries.
- [ ] No-results, offline, timeout and service-error states are explicit and do not fabricate data.

Separate deterministic UI tests from public Photon/Valhalla integration checks.

See SRCH-01 to SRCH-07 and ROUTE-01 to ROUTE-05 in the scenario catalogue.

## Stage 4 — active navigation

- [ ] Navigation starts from a valid route preview.
- [ ] Guidance panel, next manoeuvre and trip summary render.
- [ ] Synthetic location updates advance route progress and guidance.
- [ ] Off-route detection and bounded rerouting are exercised.
- [ ] Reroute failures preserve the current guidance and show a recovery state.
- [ ] Arrival and explicit end-navigation states are handled.
- [ ] Background/foreground behaviour follows the documented session lifecycle.

See NAV-01 to NAV-07 in the scenario catalogue.

## Stage 5 — wider product scenarios

- [ ] Charging discovery, tariff provenance/freshness and route charging suggestions.
- [ ] Saved trips and trip restoration.

These tests remain out of scope until the corresponding application capability exists in the APK under test.

## Stage 6 — Android Auto

- [ ] Desktop Head Unit connect, disconnect and reconnect.
- [ ] Supported navigation template and map-surface lifecycle.
- [ ] Driver-safe browse and charging-stop flows.
- [ ] Shared phone/car navigation-session behaviour.
- [ ] Physical head-unit acceptance.

A hosted phone emulator cannot satisfy these Android Auto acceptance criteria.

## Evidence for every run

- Android-nav source commit SHA and upstream workflow run ID.
- Upstream artifact name, artifact digest and APK SHA-256.
- APK package name, version and ABI.
- Emulator API level, system image, device profile and acceleration mode.
- Scenario-level JUnit XML and a concise machine-readable summary.
- Screenshots for key screens and failures.
- UI hierarchy and relevant bounded logcat.
- Explicit classification of app failures versus external dependency failures.

## Constraints

- Use synthetic GPS coordinates and test destinations only.
- Do not store real location history, personal destinations, tokens or production credentials in this repository or evidence.
- Tests must distinguish app defects from unavailable public prototype services.
- Network-dependent tests must report dependency failures separately from deterministic UI assertions.
- A command that injects emulator GPS is not proof that the app consumed the fix or placed the marker correctly; assert app-visible behaviour independently.
