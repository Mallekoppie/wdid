# 02: Bootstrap admin and invite-gated registration

**What to build:** A deployment creates the first account with a bootstrap secret, and that account becomes admin. The admin can issue, list, and revoke single-use invite codes from the CLI. A later person registers with an invite code, logs in, and reaches the app. Registration without a valid invite fails with a clear error.

**Blocked by:** None (can start immediately)

**Status:** ready-for-human

- [x] The first account created with the bootstrap secret becomes admin.
- [x] Later registration requires a single-use invite; reusing an invite is rejected.
- [x] The CLI can create, list, and revoke invites.
- [x] Login and registration screens use the auth RPCs.
- [x] Local login and Zitadel OIDC still work.
- [x] Tests cover bootstrap, invite success, invite reuse, and invalid or missing invites.

## Comments

Implemented on branch `master`.

- `WDID_REGISTRATION_SECRET` is now `WDID_BOOTSTRAP_SECRET`. The first
  registration must present it and becomes `admin`; afterwards it is rejected.
- Invites live in `sys:invites` keyed by a SHA-256 hash of the code. Codes are
  single-use, bound to the invited email, and shown once by
  `wdid invite create --email`.
- Invite redemption and account creation share one BoltDB transaction, so a
  failed registration leaves the invite unused.
- `wdid invite create|list|revoke` read only `WDID_DB_PATH`; they do not need the
  serving secrets.
- `auth.proto` carries `invite_code` and `bootstrap_secret`;
  `GetAuthConfig` reports `bootstrap_required` plus invite registration.
- The Flutter login screen now calls the auth RPCs over gRPC-Web for local
  login, invite registration, and first-account bootstrap.
- Zitadel token verification is unchanged and `GetAuthConfig` still reports the
  configured OIDC settings. The browser OIDC redirect flow remains out of scope
  (the button explains that when OIDC is enabled).

Review follow-ups applied:

- `.gitignore`'s `data/` rule also matched `web/lib/data/`, so the new auth
  adapter (and the existing repository sources) could not be committed. The
  rules are now root-anchored.
- Field 4 is reserved rather than reused by `invite_code`.
- Invite/bootstrap credentials are validated before bcrypt runs, and
  `Store.CheckInvite` gives the service a read-only pre-check; the write
  transaction still re-checks and consumes the invite.
- Added tests for a revoked invite, for redeeming the code the CLI printed, and
  for the real `GrpcAuthApi` field/error mapping via its `AuthRpc` seam.

Known limitation: the CLI opens the BoltDB file directly, and bbolt takes an
exclusive lock. Invite commands therefore require the service to be stopped.
The README says so and the CLI reports the lock. Live invite management would
need an admin RPC (deferred, like the Users & Access screen).

2026-10-24: Manual run-through found the app never routed to the login screen:
the router started at `/today` with no session, so every RPC failed with
`missing or malformed bearer token`. Fixed by adding an auth redirect guard
(`web/lib/routing/app_router.dart`) and deferring data loads until a session
exists; regression tests live in `web/test/auth_gate_test.dart`. `make check`
passes (252 Flutter tests).
