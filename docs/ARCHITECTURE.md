# Architecture

## Components

| Component | Responsibility |
|---|---|
| Private Android-nav repository | Source code, unit tests, trusted APK build |
| Public android-nav-ux-lab repository | Emulator orchestration, UI tests, screenshots and reports |
| GitHub Actions | Temporary Linux runner and emulator lifecycle |
| Cross-repository artifact access | Retrieve the exact APK from a trusted Android-nav workflow run |
| Test evidence | APK SHA-256, source commit, JUnit XML, screenshots and logcat |

The lab does not clone or build the private application source. It tests the
APK produced by the private repository's trusted workflow.

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

## APK / emulator ABI constraint

The inspected Android-nav app Gradle configuration sets
`abiFilters += "arm64-v8a"`. The current CI workflow also verifies ARM64
release output. This is appropriate for the physical Galaxy S23 but is not
compatible with a standard x86_64 Android emulator when the APK contains
ARM64-only native libraries.

The lab should use a dedicated x86_64 test APK, produced by a test-only build
configuration in Android-nav. The production and signed DEV release variants
must remain ARM64-only. The test APK should use a distinct application ID or
be otherwise clearly separated from release artifacts, and should contain no
production signing material.

Do not silently attempt to install an ARM64-only APK on an x86_64 emulator.
Fail early with a clear ABI diagnostic.

## Workflow shape

1. Manual dispatch with an explicit Android-nav workflow run ID or commit SHA.
2. Download the matching test APK from the private Android-nav Actions artifact.
3. Verify source SHA metadata, APK SHA-256, package name and native ABI.
4. Start a pinned Android x86_64 emulator image on a GitHub-hosted Linux runner.
5. Install APK and wait for boot completion.
6. Run smoke/UI tests and collect screenshots plus logcat on both success and failure.
7. Upload test evidence with short retention.
8. Terminate the emulator with the runner.

The workflow must fail if the artifact is missing, stale, has the wrong package
or ABI, or does not match the requested source commit.

## Test framework direction

Use AndroidX Test / UI Automator for black-box app interaction. Add Compose
testing APIs only if the application exposes suitable test tags and the
additional test dependencies are justified. Keep tests independent of private
backend credentials; use deterministic fixtures or explicitly configured
non-production test services.
