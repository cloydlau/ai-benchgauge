# Development and release checks

For changes to a desktop interface, obtain real Windows WPF and Mac AppKit / SwiftUI screenshots using the same fixture and content viewport. Follow [docs/visual-comparison.md](docs/visual-comparison.md).

- Capture before and after a style fix and compare each affected state's shown, refreshed and settled frames. Add fixture scenarios for newly changed states; the existing fixture is not exhaustive.
- Review layout, alignment, clipping, spacing, controls, quotas, empty/error states, long names, supported languages and themes. Record intentional platform differences and unresolved differences in the PR.
- Link the CI run and its `native-visual-comparison` artifact, including the source revision, OS and actual DPI. Do not substitute a browser imitation, scaled PNG, unit tests or successful capture for native visual review.
- If a reported issue depends on Windows 10/11 or display scaling, reproduce it on that OS and real scaling before claiming it fixed. Server 2022 / 100% is only the current CI coverage.
- Do not claim a visual fix is verified without the relevant captures. Continue available implementation and capture work; explicitly report missing environment coverage.
- Release publishing depends on the `native-visual-review` protected environment. Only a human may approve it after reviewing that run's report. Agents must not approve or bypass this gate, remove required reviewers, or manufacture a review record.

Generated comparison screenshots stay in ignored `work/` and CI artifacts. Existing privacy/media commit checks remain applicable to any screenshots submitted to Git history.
