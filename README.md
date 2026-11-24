# Android-Nav UX Lab

A public, GitHub-hosted Android emulator test harness for the private
[Android-nav](https://github.com/scollorec/Android-nav) application.

## Purpose

- Install a precisely identified Android-nav emulator APK on a temporary cloud emulator.
- Exercise repeatable user journeys, including lifecycle, permissions, map/location, search, routing and active navigation.
- Capture screenshots, UI hierarchy, logcat and machine-readable scenario reports.
- Tie every result to the exact Android-nav source commit and APK checksum.
- Destroy the emulator when the GitHub Actions job ends.

This repository contains test infrastructure only. It must not contain the
Android-nav application source, signing keys, private endpoints, API tokens,
real user location history or production credentials.

Before changing this repository, read the mandatory [engineering instructions](AGENTS.md).

## Current status

**Stage 0 — emulator and artifact plumbing: complete.** Hosted UX Lab
[run #12](https://github.com/scollorec/android-nav-ux-lab/actions/runs/45369689487)
completed successfully. It verified the trusted APK artifact, KVM acceleration,
Android framework readiness, APK installation, launcher completion, app foreground,
MapLibre accessibility-node presence, a viewport-detail heuristic and no detected
crash/ANR. It did not test GPS, search, routes or navigation.

The tested app artifact came from the trusted Android-nav
[run #173](https://github.com/scollorec/Android-nav/actions/runs/44998552450):
- Source branch: `feature/t1-tesla-experience`
- Source commit: `31dbb27aa81cc37b889a01610aab3db23aecc560`
- Artifact: `android-nav-emulator-x86_64-release-apk`
- APK filename: `Android-Nav-emulator-x86_64.apk`
- Package: `com.scollorec.androidnav.emulator`
- ABI: `x86_64`

The detailed [user-scenario catalogue](docs/USER_SCENARIOS.md) defines the full
coverage target and distinguishes verified, planned, dependency-gated, device-only
and not-yet-implemented capabilities. The [test plan](docs/TEST_PLAN.md) tracks
the staged implementation. The first functional expansion is synthetic GPS,
location-marker validation and map re-centering.

## Operating model

1. Select a successful, trusted Android-nav workflow run and its exact source commit.
2. The manually dispatched lab workflow retrieves the emulator APK artifact from
   the private Android-nav repository using a narrowly scoped read-only GitHub token
   stored as an Actions secret.
3. The workflow verifies artifact identity, APK checksum, package and ABI.
4. It boots a temporary Android x86_64 emulator, installs and launches the app,
   and runs the automated user-scenario suite.
5. Screenshots, UI hierarchy, logcat and test reports are uploaded as short-retention lab artifacts.

The lab must not clone or build private Android-nav source code. The cross-repository
token must never be exposed to untrusted pull-request code or printed in logs.

## Running the cloud smoke test

See [the cloud smoke test runbook](docs/RUN_CLOUD_SMOKE_TEST.md) for one-time token setup and the first manual run. The workflow is [Android-nav cloud emulator smoke test](.github/workflows/android-nav-emulator-smoke.yml).

## Cost

The repository is public. Standard GitHub-hosted Linux runner time for public
repository Actions workflows is free under GitHub's current policy. Artifact
storage and retention remain subject to GitHub limits and policy.
