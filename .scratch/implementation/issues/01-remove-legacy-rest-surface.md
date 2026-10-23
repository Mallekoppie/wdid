# 01: Remove the legacy REST surface

**What to build:** The service exposes its API only through Connect RPCs. The old non-RPC domain routes for auth, initiatives, entries, timer, summary, and export are gone, and `/healthz` remains for liveness. The app still starts, the auth RPCs still work, and the Flutter demo is unaffected because it makes no REST calls.

**Blocked by:** None (can start immediately)

**Status:** ready-for-human

- [x] Non-RPC domain routes are removed; `/healthz` still returns 200.
- [x] Connect auth RPCs still work over Connect and gRPC-Web.
- [x] No unused REST dependencies remain.
- [x] The service builds and `make check` passes.

## Comments

Implemented on branch `master`. `internal/api` and its handler tests are gone;
`/healthz` moved to `cmd/wdid` with tests asserting it is served and that the
non-RPC route table no longer registers any `/api/v1/...` domain route,
including the parameterized detail paths. The deployed handler falls through
unmatched paths to the SPA, so an unknown `/api/...` GET serves `index.html`
rather than a 404; no REST handler is reachable either way.

`gorilla/mux` is no longer a direct dependency (goslow still pulls it in
indirectly), the dead REST-only context helpers were removed from
`internal/auth`, and the removed REST paths were dropped from the goslow
unauthenticated-path list. The legacy REST documentation was removed from
`README.md` and `web/README.md`.

`internal/export` and the initiative/entry store methods now have no HTTP caller;
they are deliberately retained for the M2/M5 RPC slices that rebuild timer,
entry, and summary behaviour.

`make check` also surfaced a pre-existing test-isolation bug:
`TestPlatformConfigLocalOnlyUsesLocalJWT` failed whenever `WDID_DEV_MODE=true`
was exported, as `make` does. The test now clears dev mode explicitly.
