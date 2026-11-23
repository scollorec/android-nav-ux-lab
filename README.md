# Android-Nav UX Lab

A public, GitHub-hosted Android emulator test harness for the private
[Android-nav](https://github.com/scollorec/Android-nav) application.

## Purpose

- Install a precisely identified Android-nav test APK on a temporary cloud emulator.
- Run automated launch, navigation and UI checks.
- Capture screenshots, logcat and machine-readable test reports.
- Tie every result to the exact Android-nav source commit and APK checksum.
- Destroy the emulator when the GitHub Actions job ends.

This repository contains test infrastructure only. It must not contain the
Android-nav application source, signing keys, private endpoints, API tokens,
real user location history or production credentials.

## Current status

**Bootstrap / architecture validation.** The repository has no test workflow yet.

The existing Android-nav CI currently packages the POC/DEV debug APKs for
ARM64 only. The release configuration explicitly restricts native libraries
to `arm64-v8a`. A standard GitHub-hosted x86_64 emulator cannot install that
APK when it contains ARM64-only native libraries. Before end-to-end app testing,
Android-nav needs a dedicated x86_64 test APK build (without changing the
signed ARM64 release APK), or we must validate an ARM64 emulator image and
accept its likely performance penalty.

See [architecture and constraints](docs/ARCHITECTURE.md) and
[test plan](docs/TEST_PLAN.md).

## Operating model

1. A trusted Android-nav build produces a dedicated test APK and records its
   source commit.
2. A manually dispatched workflow in this repository retrieves that artifact
   from the private Android-nav repository using a narrowly scoped read-only
   GitHub token stored as an Actions secret.
3. The workflow verifies the APK checksum and package/ABI, boots a temporary
   emulator, installs and launches the app, and runs UI tests.
4. Screenshots, logcat and test reports are uploaded as short-retention
   workflow artifacts.

The lab workflow must not run for pull requests from forks and must not expose
the cross-repository token to untrusted code.

## Cost

The repository is public. Standard GitHub-hosted Linux runner time for public
repository Actions workflows is free under GitHub's current policy. Artifact
storage and retention remain subject to GitHub limits and policy.
