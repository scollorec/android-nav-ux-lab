# Android-Nav UX Lab

A public, GitHub-hosted Android emulator test harness for the private
[Android-nav](https://github.com/scollorec/Android-nav) application.

## Purpose

- Install a precisely identified Android-nav emulator APK on a temporary cloud emulator.
- Run automated launch, navigation and UI checks.
- Capture screenshots, logcat and machine-readable test reports.
- Tie every result to the exact Android-nav source commit and APK checksum.
- Destroy the emulator when the GitHub Actions job ends.

This repository contains test infrastructure only. It must not contain the
Android-nav application source, signing keys, private endpoints, API tokens,
real user location history or production credentials.

## Current status

**Bootstrap / integration.** The Android-nav repository already builds and
uploads a dedicated x86_64 emulator APK from trusted feature-branch pushes.

Verified workflow evidence:
- Workflow: [Option B Android POC](https://github.com/scollorec/Android-nav/actions/workflows/option-b-poc.yml)
- Successful run: [#173 — build one source commit on phone and emulator](https://github.com/scollorec/Android-nav/actions/runs/44998552450)
- Artifact: `android-nav-emulator-x86_64-release-apk`
- APK filename: `Android-Nav-emulator-x86_64.apk`
- Package: `com.scollorec.androidnav.emulator`
- ABI verification: `x86_64`
- Artifact retention: 7 days

No Android-nav Gradle or APK build changes are required for the initial lab integration.

## Operating model

1. Select a successful, trusted Android-nav workflow run and its exact source commit.
2. The manually dispatched lab workflow retrieves the emulator APK artifact from
   the private Android-nav repository using a narrowly scoped read-only GitHub token
   stored as an Actions secret.
3. The workflow verifies artifact identity, APK checksum, package and ABI.
4. It boots a temporary Android x86_64 emulator, installs and launches the app,
   and runs UI tests.
5. Screenshots, logcat and test reports are uploaded as short-retention lab artifacts.

The lab must not clone or build private Android-nav source code. The cross-repository
token must never be exposed to untrusted pull-request code or printed in logs.

## Cost

The repository is public. Standard GitHub-hosted Linux runner time for public
repository Actions workflows is free under GitHub's current policy. Artifact
storage and retention remain subject to GitHub limits and policy.
