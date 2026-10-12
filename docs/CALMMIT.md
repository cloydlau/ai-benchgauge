# Calmmit

`calmmit.config.json` points at `../calmmit`. Set `CALMMIT_PATH` to use another local checkout. The client executes live source; no npm package or publication is needed. Node 22.18+ runs the coordinator; Swift/C# remain the native compilers and test runners.

- `node Scripts/ci-checks.mjs`: configured syntax, full native tests and packaged build.
- `MODEL_NAME=<actual model> Scripts/commit.sh -m "fix(core): ..."`: shared private-index commit, identity, validation and media privacy gates.
- `MODEL_NAME=<actual model> node Scripts/calmmit.mjs identity`: show attribution without committing.
- `node Scripts/calmmit.mjs config`: inspect effective feature switches and profile order.
- `steps.tests: false`: skip unit tests in checks, commits and post-rebase validation, including the packaging hook. Standalone make-app.sh retains its test gate by default.

This repository explicitly enables lint, tests, build, secrets, media, commit review, model-generated messages, split commits and AI repair. It disables format, unused, dependency audit, optional alint, automatic push, dependency upgrades and background jobs in `calmmit.config.json`. `steps` selects checks, `profiles` orders them, and `commit` and `repair` control commit behavior.

The project's test-input signature, platform test command selection, test cache, packaging, signing, watcher and application restart remain project hooks. The build hook only reuses a passing receipt whose signature still matches the current sources. Shared commit generation uses watrek's validated hunk plan; explicit COMMIT_CODEX_MESSAGE=0 uses one local commit. Supported commit options: -m, --identity, --dry-run. History rewriting is not a passthrough option of this entry.

GitHub Actions fetches the shared source into `.calmmit-library` for checks, macOS releases and Windows builds. Set repository variables `CALMMIT_REPOSITORY` to the library's GitHub `owner/repo` and `CALMMIT_SHA` to a reviewed full 40-character commit SHA. The workflows validate both settings and set `CALMMIT_PATH` to that checkout before loading any shared modules. The shared library is the private repository `cloydlau/calmmit`. Set `CALMMIT_REPOSITORY=cloydlau/calmmit` and pin `CALMMIT_SHA` to a reviewed, tested commit already pushed there. Configure `CALMMIT_SSH_KEY` as an Actions repository secret containing a dedicated SSH private key whose public key is a read-only deploy key on the library repository. The key grants access only to that source repository; each checkout validates its presence and uses `persist-credentials: false`. Do not use a personal token or grant write access to the library. Fork pull requests do not receive this secret and cannot run the private-source checks without a trusted maintainer run. Local use continues to read `../calmmit` and needs no GitHub repository or npm publication.
