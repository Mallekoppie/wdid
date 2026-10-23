# 02: Bootstrap admin and invite-gated registration

**What to build:** A deployment creates the first account with a bootstrap secret, and that account becomes admin. The admin can issue, list, and revoke single-use invite codes from the CLI. A later person registers with an invite code, logs in, and reaches the app. Registration without a valid invite fails with a clear error.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The first account created with the bootstrap secret becomes admin.
- [ ] Later registration requires a single-use invite; reusing an invite is rejected.
- [ ] The CLI can create, list, and revoke invites.
- [ ] Login and registration screens use the auth RPCs.
- [ ] Local login and Zitadel OIDC still work.
- [ ] Tests cover bootstrap, invite success, invite reuse, and invalid or missing invites.
