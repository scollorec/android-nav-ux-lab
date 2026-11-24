# UX test plan

## Stage 0 — emulator and artifact plumbing

- [ ] Obtain a dedicated x86_64 test APK from a trusted Android-nav CI run.
- [ ] Verify the artifact's source commit and SHA-256.
- [ ] Enable KVM permissions where `/dev/kvm` is available and verify `emulator -accel-check`; use TCG only as an explicit fallback.
- [ ] Boot the selected x86_64 emulator image on a GitHub-hosted Linux runner with the verified acceleration mode.
- [ ] Wait for `sys.boot_completed`, InputManager registration and a responsive Settings provider before input or settings operations.
- [ ] Install the APK and verify the expected package is present.
- [ ] Launch the main activity and capture a baseline screenshot.
- [ ] Capture logcat and upload evidence even when a test fails.

## Stage 1 — launch and lifecycle

- [ ] Cold launch reaches the expected initial screen.
- [ ] App remains stable after background / foreground.
- [ ] Rotation or supported window-size changes do not crash the app.
- [ ] Permission-denied and permission-granted states are handled.

## Stage 2 — map and location

- [ ] MapLibre MapView appears in the UI hierarchy and the captured viewport contains visible map detail; treat the latter as a visual heuristic, not semantic tile/route validation.
- [ ] Synthetic GPS location is injected.
- [ ] User-location marker appears.
- [ ] Re-centre action returns the camera to the injected location.
- [ ] Stale or unavailable location is communicated correctly.

## Stage 3 — destination search and route preview

- [ ] Search field accepts a query.
- [ ] Results render and are selectable.
- [ ] Selecting a destination creates a route preview.
- [ ] Empty, offline and service-error states are handled without fabricated data.

## Stage 4 — active navigation

- [ ] Navigation can start from a route preview.
- [ ] Guidance panel and next-manoeuvre content render.
- [ ] Synthetic location updates advance route progress.
- [ ] Off-route behaviour and rerouting states are exercised.
- [ ] Arrival state is handled.

## Evidence for every run

- Android-nav source commit SHA.
- Workflow run ID and artifact name.
- APK SHA-256, package name, version and ABI.
- Emulator API level, image and device profile.
- JUnit XML and concise test summary.
- Screenshots for key screens and failures.
- Logcat captured on failure (and a bounded success log where useful).

## Constraints

- Use synthetic GPS coordinates and test destinations only.
- Do not use real location history, personal destinations or production tokens.
- Tests must distinguish app defects from unavailable public prototype services.
- Network-dependent tests should report dependency failures separately from
  deterministic UI assertions.
