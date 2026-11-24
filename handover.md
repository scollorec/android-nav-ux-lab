# Android-Nav UX Lab handover

**Updated:** 2026-11-24 15:15 UTC  
**Repository:** `scollorec/android-nav-ux-lab`  
**Default branch:** `main`  

## Purpose and scope

The public UX Lab is a black-box test harness for the private `scollorec/Android-nav` application. It consumes a trusted APK artifact; it must not clone or contain private app source, signing material, production credentials or real location history.

Keep UX Lab changes separate from Android-nav application fixes. Use synthetic GPS coordinates and synthetic destinations only.

## Current validated baseline

- Android-nav source workflow run: [#173](https://github.com/scollorec/Android-nav/actions/runs/44998552450)
- Android-nav source SHA: `31dbb27aa81cc37b889a01610aab3db23aecc560`
- Trusted artifact: `android-nav-emulator-x86_64-release-apk`
- APK: `Android-Nav-emulator-x86_64.apk`
- Package: `com.scollorec.androidnav.emulator`
- Build label observed in UI: `Build #173`
- ABI: `x86_64`
- UX Lab run #12 passed the 7 smoke assertions and framework readiness check using KVM. It proves emulator/APK/install/launch/MapLibre-surface plumbing only; it does not prove GPS, search, routing or navigation.

## Latest hosted run — GPS scenario failure

[UX Lab run #13](https://github.com/scollorec/android-nav-ux-lab/actions/runs/45386108369) ran on `main` at the pre-documentation merge SHA `9b0b5be62721d00d2dcd76949e2730570184b88f`.

- Runner and emulator booted successfully with KVM.
- Trusted APK validation, install and launch succeeded.
- The seven smoke assertions and the harness regression step completed successfully.
- The six-case location suite reported **2 passed / 4 failed**:
  - Foreground location permissions granted before launch: PASS.
  - Initial synthetic location marker centred: FAIL.
  - Follow after second synthetic fix: FAIL.
  - Marker moves off-centre after map pan: FAIL.
  - Recenter control discovered and tapped by accessibility: PASS.
  - Marker/camera returns to centre after recenter: FAIL.
- All four marker screenshots reported: `No qualifying red location-marker component found`.
- Final `dumpsys location` recorded `48.860598, 2.337600` and an app-attributed high-accuracy GPS request. This is provider-level evidence only; it does not prove app callback delivery or map rendering.
- Evidence artifact: [run #13 artifact](https://github.com/scollorec/android-nav-ux-lab/actions/runs/45386108369/artifacts/14917260922). It contains screenshots, JUnit XML, provider dump, UI hierarchy and bounded logcat.
- Do not rerun the same test unchanged or downgrade the assertions to turn this into a pass.

## Repository changes

- PR #1 merged the 39-scenario catalogue and initial synthetic GPS/recenter harness: [PR #1](https://github.com/scollorec/android-nav-ux-lab/pull/1).
- PR #2 merged the run #13 failure record, corrected scenario statuses and an engineering rule distinguishing GMS/provider state from proof that the app consumed a location fix: [PR #2](https://github.com/scollorec/android-nav-ux-lab/pull/2).
- The run #13 screenshot checker originally searched for red, but the app specification uses a blue marker for a fresh fix and green for a stale/unusable fix. Re-inspection found neither app-specified marker in the map area. Branch `fix/location-marker-colour-check` updates the checker to detect the blue/green circular marker, replaces the red-arrow test fixtures with blue circles, and clarifies the historical evidence. It does not reclassify run #13 or claim the scenarios pass. The manual-only emulator workflow now allowlists `feature/uxlab-gps-location-follow` alongside the existing `feature/t1-tesla-experience` source branch; exact run/SHA/artifact digest/package/ABI/checksum checks remain intact.
- PR #2 merge commit: `d2e686ff8e1f6853bb67136e445f71259a929774`.

## Application-repository gate

The private app repository was checked read-only after run #13. Its `AGENTS.md` requires reading the milestone handoff/plan and completing the current milestone's acceptance gates before source changes. Current `docs/HANDOFF.md` records `milestone: M1`, `status: D2_ACCEPTED`, `next_milestone: D2 merge approval`; it also states that PR #10 is closed/unmerged and explicit merge approval is required. Therefore no Android-nav source edits or app PR merge were made as part of this UX Lab task. Any location correction must first be aligned with the app repository's milestone owner/gate, then follow its unit-test, signed DEV APK, Galaxy S23 acceptance and handoff-update protocol.

The 39 catalogue rows currently classify as: **0 VERIFIED, 2 PARTIAL, 3 FAIL, 1 DEPENDENCY-GATED, 27 PLANNED, 3 NOT IN CURRENT POC, 3 DEVICE-ONLY**. The seven passing smoke assertions in run #13 are harness checks, not seven additional verified user journeys.

## Next actions

1. **Application defect investigation (blocking):** in the private Android-nav repository, inspect the location permission/state flow, `FusedLocationProviderClient` callback registration and delivery, location marker/layer visibility, initial camera policy, map follow state and recenter action. Use run #13 evidence as the reproduction. Keep this work in the app repository, not this public lab.
2. Add app-level observable telemetry or a test seam where appropriate so tests can distinguish callback receipt from Android provider state. Do not rely on `adb emu geo fix` or `dumpsys location` alone.
3. Build a new trusted emulator APK from the corrected app revision and record its exact source SHA, artifact ID/digest and APK checksum.
4. Dispatch the manual-only UX Lab workflow on `main` using the new trusted run ID and exact SHA. The workflow must remain constrained to `workflow_dispatch`, `main`, least-privilege permissions and trusted artifact validation.
5. Inspect the new run's jobs, complete failing logs (if any), screenshots, JUnit and artifact. Mark LOC-01/02/03 verified only when their app-visible assertions pass on a hosted emulator.
6. Once Stage 2 is genuinely passing, automate the next deterministic journeys: destination search/results selection, route preview and map interaction during navigation. Keep Photon/Valhalla dependency tests separate from deterministic UI tests.
7. Run and report the full 39-scenario catalogue by status. Do not label planned, dependency-gated, device-only or not-implemented scenarios as passed. Android Auto remains a separate Desktop Head Unit/physical-device programme.

## Execution constraints

- Workflow is intentionally manual-only. Do not add `push`, `pull_request` or `pull_request_target` triggers.
- Do not expose `ANDROID_NAV_READ_TOKEN` outside the trusted artifact-download steps.
- Do not change Android-nav app source from this repository.
- Do not mark a scenario PASS without hosted evidence for its stated assertion.
- For each user interaction on the app/lab project, update this handover with the actual work, exact commits/runs, evidence, blockers and next action.
- Marker-checker correction PR: [PR #5](https://github.com/scollorec/android-nav-ux-lab/pull/5) from `fix/location-marker-colour-check`; changes are confined to the public lab and require a new hosted run before any scenario status changes.
- Handover PR [#3](https://github.com/scollorec/android-nav-ux-lab/pull/3) was merged to `main` as commit `69f241c033da26e08dbba82c4baab51a7b0af059`; the merged file was fetched back and verified.
