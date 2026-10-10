# xAI shared login

BenchGauge and CC Switch share one login store, not independent copied accounts.
`CCSwitchProviderStore.resolveInstall().xaiAuthURL` resolves the actual CC Switch
configuration directory, including `app_config_dir_override` overrides.

## Authorization

Click an xAI quota card showing an expired or missing login. BenchGauge discovers
xAI's device, token and userinfo endpoints from the official OpenID document,
validates HTTPS and `auth.x.ai`, requests a device code, and opens the supplied
`accounts.x.ai/oauth2/device` URL with the matching `user_code`. The opaque device
code stays in the shared Swift actor; the native app only receives a browser URL,
user-visible code, expiry and random attempt ID. Redirects are rejected by the
existing quota HTTP transport.

Polling respects the server interval. `authorization_pending` keeps waiting;
`slow_down` adds five seconds to subsequent polls. Denial, local/server expiry and
cancelled attempts do not save a login. Close cancels authorization; retry creates
a new link. Userinfo validates the account belonging to the issued access token.
Reauthorizing an existing selected account must return the same account ID.

The store retains CC Switch's version, account map, record keys, unrelated metadata
and other accounts. Successful authorization updates the selected account's
refresh token, login label, authentication time and `requires_reauth`, then saves
with an atomic replacement and 0600 permissions on Unix. Windows uses the profile
folder ACL. Access tokens and device codes are never persisted. Before replacement
it checks the selected account/token/default and the current file bytes again;
a login changed in the other app while the browser was open is not overwritten.
This is optimistic conflict detection, not a cross-process lock honored by CC Switch.

The protocol uses the same public Grok CLI client ID and scopes that CC Switch
already uses. Contract checked on 2026-10-10 against:

- xAI discovery: `https://auth.x.ai/.well-known/openid-configuration`
- CC Switch `src-tauri/src/proxy/providers/xai_oauth_auth.rs`, upstream revision
  `ef24a0191242dda380a4ccd2dc264c8a309c6378` (4.0.6).

## Reusing the login in both directions

CC Switch → BenchGauge: the native apps check noncredential file metadata every
two seconds, including atomic replacement and logout. They refresh xAI when the
store changes. The quota client's cached access token is tied to the exact
selected account and refresh token; a replacement for the same account also
invalidates that cache.

BenchGauge → CC Switch: the newly authorized refresh token is written directly to
that same store. A stopped CC Switch reads it on its next launch. CC Switch 4.0.6
loads this store only while creating `XaiOAuthManager`; it has no public hot-reload
endpoint. An already running instance must restart to use the replacement. The
Mac completion window has a **Restart CC Switch** button that requests a normal
quit, waits up to ten seconds, and relaunches the installed bundle. It does not
force-kill a refusing process, and authorization never restarts the proxy without
the user selecting this button. Windows displays the restart instruction.

This implements shared authorization with reload on CC Switch launch, not live
cross-process token coordination. CC Switch still holds its own in-memory access
and refresh tokens. Its later credential mutations do not reload external changes,
so concurrent token rotation is not guaranteed safe by that client. Fully live
bidirectional renewal needs CC Switch to reload before reads/mutations and cooperate
on serialization; BenchGauge cannot add that behavior to an unmodified CC Switch.
No claim of an end-to-end live CC Switch proxy recovery is made from fixture tests.

## Validation

The offline tests exercise successful shared-file round trips, reauth, metadata
preservation, account mismatch, changes during authorization, cancellation during
in-flight token/userinfo requests, polling/backoff, expiry, denial, network retry,
trusted hosts, corrupt stores, missing token/identity and secure storage. A quota
regression test replaces the same account's CC Switch refresh token and verifies
the next request uses a new access token.

`Tests/fixtures/xai-device-login.json` covers seven dialog states in English,
Simplified Chinese and Traditional Chinese, light/dark and three checkpoints.
Original Mac before/after captures and the local review stay in ignored
`work/xai-device-login/`; baseline captures show the earlier quota panel because
that revision had no device login dialog. The Mac-only restart button is an
intentional platform difference. Windows native screenshots and a source-matched
CI artifact remain required for complete desktop visual review.
