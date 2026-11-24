# Engineering Instructions — Android-Nav UX Lab

These instructions are mandatory for engineers and coding agents changing this repository. They apply to GitHub Actions, emulator orchestration, shell/Python scripts, APK handling and test evidence.

The standard is production engineering: understand the real execution environment, make the smallest correct change, prove it with reproducible tests, and report only what the evidence establishes.

## 1. Engineering principles

1. **Understand before changing.** Read the complete workflow, every script it invokes, the related tests and runbook, and the exact third-party Action implementation. Do not infer runtime behaviour from an Action's README or input names.
2. **Diagnose the first failing operation.** Inspect the newest run, jobs, first failed step and complete log. Identify the first failing command, shell, working directory and exit code before editing.
3. **Reproduce deterministically.** Turn the failure into a regression test. A fix is incomplete until that test fails on the old behaviour and passes on the corrected behaviour, where practical.
4. **Make small, reviewable changes.** One coherent change at a time. Avoid broad replacements, unrelated cleanup and speculative changes. Never build on an unverified intermediate state.
5. **Prove the exact revision.** Test the intended content, inspect the commit diff, then fetch every changed file back from GitHub. A successful write response or the existence of a path is not proof that the contents are correct.
6. **Evidence over confidence.** Never say a test passed unless the exact command completed successfully and its output or exit status was observed. Separate static checks, mocked tests and real hosted-emulator results.

## 2. Mandatory investigation before editing

Before changing a workflow or script:

- Read README.md, docs/ARCHITECTURE.md, docs/TEST_PLAN.md and docs/RUN_CLOUD_SMOKE_TEST.md.
- Read the complete affected workflow and all local scripts/tests it references.
- Inspect the actual third-party Action source for the version being used. For reactivecircus/android-emulator-runner, inspect action.yml, its script parser and the execution code. Establish whether the script input is executed as one shell process or split into commands.
- Check the current main SHA and latest Actions runs. Do not confuse a skipped push run with a test execution; inspect its jobs and step list.
- Trace workflow inputs, environment variables, GITHUB_ENV handoffs, working directories, artifact paths, retention and secret scope.
- Record the failure evidence, its first failing command and the behaviour the fix must establish.

Do not edit until the diagnosis is supported by source or run evidence.

## 3. Workflow execution contract

### Checkout is mandatory

A job that runs repository scripts, tests or configuration must first check out the repository. Use this pattern:

    - name: Checkout test harness repository
      uses: actions/checkout@v4
      with:
        ref: ${{ github.sha }}
        persist-credentials: false

The ref value in the actual workflow must be the GitHub expression for the triggering commit SHA. The checkout step must precede every repository-local script or test. Disable persisted checkout credentials because this workflow does not push to the repository.

Add regression assertions that prove checkout exists, targets the triggering SHA, disables credential persistence and precedes the first repository-local command.

### Respect real shell semantics

The reactivecircus/android-emulator-runner implementation inspected for this project splits its script input into lines and invokes each line using sh -c. Therefore:

- Never put multi-line functions, traps, heredocs, shell state or a multi-command program inside the Action's script input.
- Keep that input to one command, such as:

    script: bash .github/scripts/emulator-smoke.sh

- Put the implementation in a checked-in Bash script with a Bash shebang and invoke it explicitly with bash.
- Re-inspect the Action implementation whenever its version changes. Do not assume the same behaviour forever.
- Workflow run steps using Bash features must explicitly select shell: bash.

Shell choice is an interface contract. Never use Bash-only syntax under POSIX sh, and never assume a script's shebang determines how a third-party Action executes its input.

For repository-owned scripts invoked explicitly as `bash path/to/script.sh`, require a regular readable file (`-f` and `-r`), not executable permission (`-x`). GitHub's repository tree may store shell scripts as mode `100644`, which is valid when Bash reads the file. Reserve `-x` checks for native executables or scripts launched directly by path. Add a regression assertion whenever a launcher validates this distinction.

### Android emulator VM acceleration

- Do not assume GitHub-hosted Ubuntu runners lack KVM. Standard Linux runners can expose `/dev/kvm` while denying access to the runner user until the documented permission rule is applied.
- Before emulator startup, apply the KVM udev rule (`KERNEL=="kvm", GROUP="kvm", MODE="0666", OPTIONS+="static_node=kvm"`), reload/trigger udev, and verify with `$ANDROID_HOME/emulator/emulator -accel-check`.
- When the check succeeds, set `ANDROID_EMULATOR_ACCEL=on` and launch with `-accel on`. If KVM is genuinely unavailable, emit a clear warning, set `ANDROID_EMULATOR_ACCEL=off` and `ANDROID_I_WANT_MY_TCG=yes`, and launch with `-accel off`.
- Do not set the TCG opt-in unconditionally at job level or hard-code `-accel off` when KVM is available. Capture both the selected mode and acceleration-check output in the evidence.
- Treat TCG as a degraded fallback, not the normal path. In run #10, Emulator 37.3.10 ran without KVM, took 554206 ms to boot, then the Android watchdog reported the system_server main thread blocked for 63 seconds and killed system_server. Do not mask this with longer timeouts.
- Regression tests must assert that KVM setup and the acceleration check precede emulator launch, the launcher uses the verified mode, and TCG opt-in is limited to the fallback path.
- References: [GitHub Actions hardware-accelerated Android virtualization](https://github.blog/changelog/2024-04-02-github-actions-hardware-accelerated-android-virtualization-now-available/); [Android Emulator acceleration](https://developer.android.com/studio/run/emulator-acceleration); [Emulator command-line acceleration modes](https://developer.android.com/studio/run/emulator-commandline).

### Android framework readiness

- Do not treat `sys.boot_completed=1` as proof that every Android framework service is registered. InputManager and the Settings provider can become available later.
- Before issuing `input keyevent` or writing system settings, poll `adb shell service check input` until it reports `found`, and query a read-only Settings key such as `settings get global window_animation_scale` to confirm that provider is responsive.
- Use bounded waits, retain failed readiness probes in the evidence bundle, and fail with a clear diagnostic when readiness is not reached.
- If a third-party emulator Action performs post-boot ADB commands internally and offers no hook before them, do not assume a later custom script can recover the job. Use a checked-in launcher with explicit readiness control, or wait for a reviewed upstream fix/release before reintroducing that Action.
- Regression tests must cover delayed service registration, delayed Settings availability and readiness timeouts. The known race is documented in [issue #489](https://github.com/ReactiveCircus/android-emulator-runner/issues/489) and proposed [pull request #495](https://github.com/ReactiveCircus/android-emulator-runner/pull/495); verify their status before relying on them.

### Preserve workflow boundaries

- The cloud emulator workflow is deliberately manual-only. Do not add push, pull_request or pull_request_target triggers without an explicit architecture and security review.
- Keep the job constrained to main.
- Keep permissions least-privilege; this lab normally needs contents: read.
- Run the harness regression tests before spending time booting the cloud emulator.
- Upload bounded diagnostics on success and failure using an always() evidence step.
- Prefer verified KVM hardware acceleration on Linux runners; use TCG only when the acceleration check proves KVM unavailable.
- Do not increase timeouts to hide deterministic setup, path or script defects.

## 4. Test strategy and required gates

Report these layers separately:

| Layer | Required checks | What it proves |
|---|---|---|
| Static | Bash syntax, Python compilation, YAML/Actions lint, whitespace checks | Syntax and basic structural validity |
| Regression | Mocked ADB success/failure cases; parse JUnit XML | Harness logic and failure reporting under controlled inputs |
| Workflow | Checkout, order, inputs, permissions, trigger policy, artifact wiring | Workflow structure and configuration |
| Hosted emulator | Actual GitHub runner and Android emulator execution | Runner, emulator, APK install and launch work |
| UI/evidence | Foreground app, UI hierarchy, MapLibre surface presence, screenshot and crash checks | Only the behaviours explicitly asserted |

Before committing, run the regression suite from a clean checkout with its dependencies. For this project:

    bash -n .github/scripts/wait-for-android-readiness.sh
    bash -n .github/scripts/launch-emulator-and-smoke.sh
    bash -n .github/scripts/emulator-smoke.sh
    python3 -m py_compile scripts/check-map-screenshot.py
    bash tests/test-emulator-readiness.sh
    bash tests/test-emulator-smoke.sh

The regression suite expects SCREENSHOT_PYTHON to identify a Python interpreter with Pillow installed, as configured by the workflow's screenshot-preparation step. Set it explicitly for local execution.

Also run available checks such as actionlint, shellcheck and git diff --check. If a tool is unavailable, say so; never imply that it ran. Validate YAML with a real YAML/Actions parser where possible, not just grep.

The regression suite must cover:

- Happy path: install, launch, foreground app, MapLibre accessibility node, visible map-viewport detail and no app crash/ANR.
- Install/package failure and app not foreground.
- MapLibre MapView accessibility node is absent from the UI hierarchy.
- Blank or nearly uniform map viewport.
- Check the actual target APK's source and runtime UI hierarchy before asserting a debug/status label. A status TextView that is set to `GONE` is not observable through UI Automator; prefer a stable accessibility node plus a separate rendered-viewport assertion.
- Do not claim a MapLibre style callback ran based only on MapView presence. The separate screenshot heuristic establishes only that the captured viewport contains visual detail.
- App crash or ANR in logcat.
- Failure diagnostics and JUnit XML are produced even when setup or an assertion fails.
- JUnit XML is parsed and expected test/failure counts are checked.
- Workflow policy: checkout and order, manual-only triggers and one-line emulator Action command.

A mocked test is not a hosted-emulator test. MAP READY in the current app means the MapLibre style callback ran; it does not prove all map tiles rendered. The central-viewport screenshot check is a heuristic, not semantic map recognition. Never claim that routes, GPS or navigation work unless separate tests establish that.

For apps using Google Play services `FusedLocationProviderClient`, distinguish provider state from app receipt. An app-attributed `WorkSource` request or a GPS/fused last location in `dumpsys location` proves only that Android/GMS has a request or provider fix; it does not prove that the app's location callback received the coordinate or that its map layer/camera updated. Capture provider snapshots and bounded logcat around each synthetic fix. Investigate `blocked - too close` messages against the exact `LocationRequest` minimum distance and the separation between injected coordinates; repeated identical fixes can be filtered normally. Require app-observable callback/test telemetry or rendered marker/camera behaviour, and do not weaken those assertions because `adb emu geo fix` or `dumpsys location` reports success.

## 5. Safe editing and GitHub commit discipline

### Before editing

- Fetch the current branch head and file blob SHA.
- Work from the exact current file contents, not an old transcript or remembered version.
- Define the intended change and invariants that must remain unchanged.
- Use exact patch anchors and assert that each expected anchor occurs exactly once.
- Prefer a structured patch or a complete known-good file over chained string replacements.
- Never perform broad/repeated replacements in long scripts. Do not let a replacement re-match text introduced by itself.
- Do not hand-encode Base64. Use UTF-8 content with the GitHub tool's supported encoding.
- After every distinct CI or runtime failure, assess whether the durable instructions are missing a reusable engineering rule. Update AGENTS.md in the same coherent change when the failure exposes a new invariant; do this as a routine review, while avoiding redundant notes for issues already covered.

### Before committing

Review the entire diff, not just the intended lines. Confirm:

- No duplicated blocks, truncation, malformed quoting or accidental encoding/binary characters.
- No unrelated files or unexpected changes.
- Paths, line endings, indentation, YAML structure and file modes are correct.
- For workflow changes, review the complete ordered step inventory and check that each intended build, test, bootstrap and execution stage appears exactly once; do not leave superseded or duplicate steps behind.
- Every script/test path referenced by the workflow exists in the checked-out tree.
- Tests invoke the exact scripts and paths that CI will invoke.
- The regression suite actually ran and its result was observed.
- Manual-only and least-privilege constraints remain intact.

For multi-file changes, construct the complete intended tree against the inspected parent commit and update the branch with an expected-head check. If main moved, stop, re-fetch and reconcile. Never overwrite concurrent work.

### After committing

1. Fetch the new commit and inspect the diff.
2. Fetch every changed file from main again.
3. Compare remote contents with the intended contents; verify line counts and key sections where useful.
4. Confirm main points to the expected commit.
5. Re-run checks against the committed revision where possible.
6. Only then report the commit as complete.

Do not make a corrective commit until the previous commit's actual contents have been inspected. If a committed file is wrong, state that plainly, restore a known-good baseline and validate the corrected file before writing again.

## 6. CI failure triage

For every failed Actions run:

1. Fetch run metadata: event, branch, SHA, status and conclusion.
2. Fetch jobs; identify skipped jobs and the first failed step.
3. Fetch the complete failing-job log.
4. Extract the first failing command, shell, working directory, relevant environment and error.
5. Verify the implicated path exists in the checked-out commit and inspect that exact revision.
6. Reproduce locally or with a deterministic mock before changing code.
7. Add a regression assertion for the discovered failure.
8. Commit only after the relevant checks pass.
9. Dispatch a new manual run against the intended main SHA.
10. Inspect its logs and artifacts. Never infer a pass from a queued, skipped or empty-job run.

Do not rerun deterministic failures unchanged. Reruns are for demonstrated transient infrastructure failures, not missing files, invalid shell syntax, bad paths or broken assertions.

## 7. Security and artifact integrity

- The public lab contains test infrastructure only, never private Android-nav source, signing keys, production endpoints, credentials or personal location history.
- Retrieve APKs only from successful, trusted source workflow runs; validate trusted branch and exact source SHA.
- Require exactly one unexpired artifact with the expected name.
- Verify the artifact ZIP digest against GitHub metadata before extraction.
- Verify APK filename, package, ABI and APK checksum before installation.
- Keep ANDROID_NAV_READ_TOKEN in a repository Actions secret, scoped to the private Android-nav repository with Actions read-only permission.
- Pass the token only to the API steps that need it. Never echo it, write it to evidence or expose it to untrusted code.
- Do not introduce fork/PR paths into the secret-bearing job.
- Use synthetic coordinates and test destinations only.

## 8. Evidence and reporting standard

Every status report must distinguish:

- **Committed:** the exact change is present on the stated branch and commit.
- **Static checks:** name the commands that ran and passed.
- **Regression tests:** state whether the complete suite executed successfully.
- **Hosted execution:** link the exact Actions run and identify which steps actually ran.
- **Application validation:** list the assertions passed and what they do not prove.
- **Outstanding blockers:** name the concrete next action and dependency.

Never say fixed, verified or passed without qualifying the level of evidence. Do not claim the emulator ran when its job was skipped. Do not describe a push run with zero jobs as a test execution.

When asked for status, inspect the live branch and latest Actions run first. Do not rely on a previous conversation summary when GitHub can be checked.

## 9. Definition of done

A workflow change is not done when code is committed. It is done only when:

- The change is reviewed against actual Action/runtime semantics.
- Static checks and the full mocked regression suite pass on the intended revision.
- Committed files have been read back and the diff verified.
- A manual hosted run executes the expected jobs and passes the required emulator and app assertions.
- Evidence is retained and linked.
- Limitations are documented and no unsupported claims are made.

If a hosted run fails, the task remains open. Diagnose and repeat this process until it passes or a genuine external blocker is identified.
