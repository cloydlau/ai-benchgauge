# GitHub icon

Selected through [Icones](https://icones.js.org/collection/tabler?s=brand-github):
`tabler:brand-github-filled` from Tabler Icons, under MIT.
`source.json` pins the upstream revision, exact SVG and license URLs, retrieval
date and SHA-256 hashes. `logo.svg` and `LICENSE.txt` are unchanged upstream files.

`node Scripts/source-logos.mjs` renders the SVG at 128×128 in `#161614` on a
transparent background to `assets/logos/github.png`; `--check` rejects stale
exports or changed source files. That PNG is a generated compatibility export,
not a second source. macOS and Windows repository buttons, the shared leaderboard
logo fallback and the GitHub Actions contributor avatar use the same output.
iPhone/iPad and the mini-program bundle it through their existing logo paths.

The full MIT notice is packaged with all four clients: the desktop Tabler
notices and the mobile source-mark notice. GitHub is a trademark of its owner;
Tabler's artwork license does not imply GitHub endorsement or grant trademark
rights. No complete icon library or remote icon service is loaded at runtime.
