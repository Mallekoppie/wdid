# 24: Final integration

**What to build:** The demo adapter is gone. Every screen reads and writes through generated Connect clients over gRPC-Web, the embedded app is served on the same origin as the RPCs, and the full loop works in a browser: capture a day, review a week, create and finalize a manager check-in, export, and restore a backup.

**Blocked by:** 23 (UI polish)

**Status:** ready-for-agent

- [ ] `DemoWdidRepository` is deleted and every screen uses generated clients.
- [ ] A real browser gRPC-Web request reaches the service.
- [ ] The embedded app and the RPC surface are served on the same origin.
- [ ] No REST or hand-written JSON path remains for a capability that has an RPC.
- [ ] The full loop works: capture, personal review, manager check-in, export, backup/restore.
- [ ] `make check` passes and the browser smoke test is recorded.
