# Running the cloud emulator smoke test

## One-time secret setup

1. In the private `scollorec/Android-nav` repository, create a **fine-grained personal access token**.
2. Restrict repository access to **only** `scollorec/Android-nav`.
3. Grant **Actions: Read-only**. GitHub documents this permission for listing workflow-run artifacts, getting artifact metadata and downloading artifact ZIPs.
4. In this public lab repository, open **Settings → Secrets and variables → Actions → New repository secret**.
5. Name it exactly `ANDROID_NAV_READ_TOKEN` and paste the token value. Do not commit it, put it in workflow inputs, or send it in chat.

The workflow only references this secret from a manually dispatched job on `main`. It has no pull-request trigger, no `pull_request_target`, and no write permissions. The token is passed only to the two API download steps and is not written to files or printed.

## First run

The existing known-good source run is:

- Android-nav run ID: `44998552450`
- Source commit: `31dbb27aa81cc37b889a01610aab3db23aecc560`
- Branch: `feature/t1-tesla-experience`
- Artifact: `android-nav-emulator-x86_64-release-apk`
- Artifact ID (at verification): `14745480165`
- Artifact ZIP SHA-256: `d2146087a470ecc0c4dac9966e4609d204ab63f819e07576e462c700c23f966c`

This artifact has a seven-day retention period from its creation on 2026-11-22. If it expires, use a newer successful trusted run that contains the same named artifact and provide that run's exact source SHA.

In GitHub, open **Actions → Android-nav cloud emulator smoke test → Run workflow**. Enter the run ID and expected source SHA above. The workflow validates that the run completed successfully, came from the trusted `feature/t1-tesla-experience` branch, and matches the SHA before downloading anything.

## What is checked

- Private workflow run status, branch, event and exact source SHA.
- Exactly one unexpired artifact with the expected name.
- Artifact ZIP digest against GitHub's artifact metadata.
- Extracted APK filename, package `com.scollorec.androidnav.emulator`, and x86_64 native ABI.
- APK SHA-256 recorded in evidence.
- Android API 35 Google APIs x86_64 Pixel 2 AVD created on the hosted runner. The workflow enables KVM permissions and verifies `emulator -accel-check`; it uses KVM when available and only falls back to TCG when the check fails. Before input/settings commands, the launcher checks boot completion, InputManager registration and a responsive Settings provider.
- APK installation, launcher execution, MapLibre MapView accessibility presence, map viewport visual heuristic and crash/ANR checks.
- Emulator output, readiness probes and test JUnit reports retained in the evidence bundle.
- Screenshot, UI hierarchy, activity dump, bounded logcat and JUnit smoke report.

The workflow first applies GitHub's documented KVM udev permission rule and checks whether KVM is usable. Hardware acceleration is preferred; TCG remains an explicit fallback and can be extremely slow on hosted runners. The selected mode and check output are retained in evidence.

The emulator is started by the checked-in launcher rather than delegating boot completion to a third-party Action. This is intentional: `sys.boot_completed=1` can be observable before InputManager and Settings are registered. The launcher waits for both before issuing unlock or settings commands. Do not reintroduce the third-party runner unless its post-boot service-readiness behaviour has been verified in the exact version selected.

The UI hierarchy assertion checks the MapLibre MapView accessibility node. The app's diagnostic `MAP READY` TextView is hidden in the normal landing UI, so it is not a valid UI-automator readiness signal. The separate screenshot and viewport check are evidence of rendered map detail, but remain a heuristic and do **not** prove semantic map-tile or route correctness.

## Evidence retention

The lab uploads the evidence bundle for five days, including on failure when the runner has produced files. The temporary hosted emulator is discarded with the job.

## Security notes

- Do not add automatic PR triggers to this workflow.
- Do not run code from forks in a job that receives `ANDROID_NAV_READ_TOKEN`.
- Do not store production credentials, signing keys, real location history or personal destinations in this repository or its artifacts.
- Use synthetic GPS coordinates and non-production test data for future navigation tests.
