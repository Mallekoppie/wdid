# 01: Remove the legacy REST surface

**What to build:** The service exposes its API only through Connect RPCs. The old non-RPC domain routes for auth, initiatives, entries, timer, summary, and export are gone, and `/healthz` remains for liveness. The app still starts, the auth RPCs still work, and the Flutter demo is unaffected because it makes no REST calls.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Non-RPC domain routes are removed; `/healthz` still returns 200.
- [ ] Connect auth RPCs still work over Connect and gRPC-Web.
- [ ] No unused REST dependencies remain.
- [ ] The service builds and `make check` passes.
