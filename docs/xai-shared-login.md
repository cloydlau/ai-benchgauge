# xAI desktop authorization

## Subscription boundaries and entitlement (2026-10-25)

A zero usage counter does not establish that a paid subscription still exists.
When the subscriptions endpoint cannot provide a current record, quota refresh
checks the current CLI settings tier. The [official Grok client](https://github.com/xai-org/grok-build/blob/main/crates/codegen/xai-grok-shell/src/tier.rs)
classifies Free and X Basic separately from paid tiers. Without an unexpired
API subscription result to reuse, an unknown, missing or failed tier response
stays unverified; it cannot become a green 100% allowance.

API subscription dates remain cached for the same account after their boundary
passes. Explicit ended records retain their actual end date; an active renewal
wins over ended history. A passed date alone is not proof of expired access, so
an unverifiable renewal shows “套餐待核实” with the last reported date. Confirmed
inactive plans show “订阅已过期” when their reported end has passed, or “未订购”
without an ended date. Their usage percentages are suppressed in the card,
help and menu bar, and do not trigger quota recovery notifications. No usage
reset is promoted to a subscription date. A date the provider never reported
cannot be reconstructed.

Shared parser/client regression tests and the native fixture
`Tests/fixtures/xai-expired-subscription.json` cover these states. Native Mac
captures and logs are kept under ignored `work/xai-expired-subscription/`.
Windows native OS/DPI captures require a Windows environment and are not
claimed by local shared-code tests or cross-compilation.

Local validation passed `./test.sh --coverage` for stable inputs, with no skipped
checks and 100% script/Swift coverage. The identical fixture produced 54 native
Mac frames before and 54 after on macOS 27.0.1 at actual 1× backing scale,
900×720 points, covering three subscription states, all three languages and
both themes. All shown/refreshed/settled pairs are pixel-identical. Reviewed
originals show complete status labels and retained dates without clipping;
confirmed inactive cards keep their existing dimmed presentation. Source hashes,
capture provenance, test receipt and review notes are in
`work/xai-expired-subscription/verification.json`.

BenchGauge now owns an independent xAI device-authorization session. CC Switch
can remain open while quota refreshes and scheduled keep-alive run. The old
requirement to quit/restart CC Switch is removed from the desktop login flow.
Existing users authorize once in BenchGauge by clicking the xAI sign-in card.
The browser still requires the user's consent; no credentials are silently copied.

## Account selection and storage

CC Switch's selected account ID is read from its actual configuration directory,
including `app_config_dir_override`. It identifies which BenchGauge session to
use, but its refresh token is never copied, renewed or written by the production
desktop flow. A fresh device grant creates BenchGauge's own refresh token.

App-owned sessions live below `PlatformPaths.applicationSupport/xai/`, in a
separate SHA-256-named JSON file for each CC Switch account ID. Rotating a shared
CC Switch token for the same account does not change this path. Switching accounts
selects a different session; an account without an app session shows sign-in.
Switching back reuses its previous app session. Without a selected shared account,
the explicitly authorized standalone session uses `unselected.json`.

The device flow binds its path and expected account ID to one selection snapshot.
Userinfo must match that account. A selection changed during browser authorization
causes `accountChanged` without saving. The selected local account, token, default
and file bytes are checked again before atomic replacement. Refresh tokens stay
in the local file (0600 on Unix; profile ACL on Windows); device codes and access
tokens remain in memory and are never returned to native surfaces or logged.

## Refresh and synchronization

Mac and Windows resolve the app-owned session for every quota/keep-alive request.
The existing two-second metadata watcher detects session saves, removal and account
selection changes. CC Switch's running state cannot block app-owned renewal.
The shared Swift token actor serializes overlapping exchanges, caches access tokens
only against the matching account/refresh token, and completes rotated-token saves
even when the initiating quota view is cancelled. Quota refresh and its existing
loading/error states remain separate from the background keep-alive schedule.

Explicit legacy shared-file callers retain the conservative process guard: they
cannot rotate a token while CC Switch is running. Production desktops no longer
select that file for authorization or requests. The protocol remains the public
Grok CLI device grant already implemented by CC Switch; discovery pins HTTPS,
issuer and trusted endpoints, and browser authorization pins `accounts.x.ai`.

This addresses BenchGauge's own quota updates. It does not claim to renew CC
Switch's independent login or alter its proxy. Upstream still caches tokens inside
`XaiOAuthManager`, without a supported public quota-only refresh/reload interface.
Its implementation was checked again on 2026-10-20:
[CC Switch xAI manager](https://github.com/farion1231/cc-switch/blob/main/src-tauri/src/proxy/providers/xai_oauth_auth.rs).

## Validation

Offline tests use synthetic accounts and transports: independent authorization and
rotation leave the shared store byte-for-byte unchanged, active CC Switch does not
block app renewal, concurrent renewals share one exchange, different accounts map
to different paths, rotating a shared token keeps the path stable, mismatched browser
accounts and selection changes do not save. The existing legacy ownership,
cancellation, polling, expiry, storage, trusted-host and quota-boundary tests remain.

The Mac and Windows dialogs share the revised independent-authorization explanation
and success/error copy. Mac's restart button was removed. The existing common
`Tests/fixtures/xai-device-login.json` covers seven states, three languages, both
themes and three capture checkpoints. A supplemental common fixture covers accountChanged and storage as well.
Native before/after Mac captures (162 frames per phase, all 54 refreshed/settled
pairs stable) and validation results are retained in ignored `work/xai-independent-login/`. Windows native
screenshots and a source-matched CI visual artifact require a Windows environment;
a local cross-build alone is not native visual verification. Real authorization
requires browser consent and is not claimed by offline fixture tests.

The final stable-source full gate passed 379 script cases, 152 mini-program cases
and 539 native package cases, including the new independent-session cases. Swift
coverage passed 100% across all 70 measured source files. Earlier runs returned
75 when concurrent workspace edits invalidated their input signatures; the final
coverage gate returned 0 with signature
`5a89f1bd70c77e50553eab062a0917dfc77847e40b70d92cddc949bd054be4fa`.
The existing workflow rebuilt and restarted the local Mac app at
2026-10-20 22:59:01 Asia/Shanghai. The new executable contains the independent
login explanation; CC Switch remained running. This confirms local delivery,
not a completed real-account authorization, Windows native visual review or a
published release.
