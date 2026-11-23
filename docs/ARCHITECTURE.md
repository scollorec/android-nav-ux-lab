# Architecture

## Components

| Component | Responsibility |
|---|---|
| Private Android-nav repository | Source code, unit tests and trusted emulator APK build |
| Public android-nav-ux-lab repository | Emulator orchestration, UI tests, screenshots and reports |
| GitHub Actions | Temporary Linux runner and emulator lifecycle |
| Cross-repository artifact access | Retrieve the exact APK from a trusted Android-nav workflow run |
| Test evidence | APK SHA-256, source commit, JUnit XML, screenshots and logcat |

The lab does not clone or build the private application source. It tests the
APK produced by the private repository's trusted workflow.

## Existing emulator APK — verified

The Android-nav workflow already has a dedicated emulator build. At commit
`31dbb27aa81cc37b889a01610aab3db23aecc560`, the workflow contains these steps:

- `Build signed Android-nav-emulator APK`
- `Verify emulator APK signature, package and ABI`
- `Upload signed emulator APK`
- `Send signed emulator APK to Telegram`

The uploaded artifact is named
`android-nav-emulator-x86_64-release-apk`, contains
`Android-Nav-emulator-x86_64.apk`, and is retained for 7 days.
The workflow verifies package `com.scollorec.androidnav.emulator`
and ABI `x86_64`.

Evidence: [successful Android-nav run #173](https://github.com/scollorec/Android-nav/actions/runs/44998552450).

**No Gradle or APK build changes are required for the lab's initial integration.**
The lab should consume this existing artifact.

## Security boundary

- The lab repository is public; all committed workflow and test code is public.
- The private-repository read token must be stored only as an Actions secret.
- Use a fine-grained token restricted to the Android-nav repository with
  Actions read access only, where GitHub supports the required artifact API.
- The token is used only in manually dispatched trusted runs.
- Never print the token or include it in artifacts.
- Never upload signing keys, private app configuration or real user data.
- Do not use `pull_request_target` or expose secrets to forked pull requests.
- Test locations and route fixtures must be synthetic and clearly labelled.

## Workflow shape

1. Manually dispatch the lab with an explicit Android-nav workflow run ID.
2. Confirm the run succeeded, is from an allowed trusted branch, and has the
   expected source commit.
3. Download artifact `android-nav-emulator-x86_64-release-apk` from that run.
4. Verify the APK SHA-256, package name and native ABI before installation.
5. Start a pinned Android x86_64 emulator image on a GitHub-hosted Linux runner.
6. Install the APK, wait for boot completion and launch the application.
7. Run smoke/UI tests and collect screenshots plus logcat on both success and failure.
8. Upload test evidence with short retention.
9. Let the runner terminate the emulator at job completion.

The workflow must fail if the artifact is missing, stale, has the wrong package
or ABI, or does not match the requested source commit.

## Test framework direction

Use AndroidX Test / UI Automator for black-box app interaction. Add Compose
testing APIs only if the application exposes suitable test tags and the
additional test dependencies are justified. Keep tests independent of private
backend credentials; use deterministic fixtures or explicitly configured
non-production test services.
