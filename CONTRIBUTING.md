# Contributing

1. Fork the repository and create a branch, for example `fix/window-selection`.
2. Make a focused change and describe the observed behavior before and after.
3. Run `bash scripts/test.sh` and `bash scripts/build.sh --adhoc`.
4. Open a pull request against `main`.

Report your macOS version, CPU architecture, target app/version, and whether Stage Manager or desktop reveal is enabled. Redact private window titles and conversations from screenshots. Do not submit signing keys, certificates, tokens, or local permission databases.

For window-engine changes, test pinning, unpinning, typing in a different app, dragging, multiple pins, and closing the target window. Report limitations honestly. Automated ordering tests do not replace native UI checks. Avoid screenshot mirrors, synthetic click forwarding, and focus-stealing fallbacks.

Pull requests from forks run tests with read-only repository permissions. Releases are created by maintainers after checks pass.
