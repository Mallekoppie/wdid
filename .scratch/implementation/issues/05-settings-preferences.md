# 05: Settings preferences end-to-end

**What to build:** A user can configure how wdid behaves: timezone, week start, daily target, default entry duration, long-timer threshold, personal-review cadence, theme, density, and the About information. Values persist per user and take effect immediately.

**Blocked by:** 03 (Category taxonomy data core)

**Status:** ready-for-human

- [x] Time settings persist: timezone, week start, daily target, default duration, long-timer threshold, and review cadence.
- [x] Appearance settings persist and apply immediately: theme and density.
- [x] About shows version, schema version, and license.
- [x] Invalid enum values and out-of-range numbers are rejected with field errors.
- [x] Settings are per user and survive a service restart.
- [x] Connect and gRPC-Web tests cover get, update, validation, and isolation.

## Comments

- Implemented and committed in `2ebd5f8` ("implement category management and settings preferences"); every box was ticked at implementation time.
- Bookkeeping reconciliation (2026-10-23): the issue file never received a Comments entry or the post-implementation status when the work landed, so both were added during a status sweep. No code changes were made during reconciliation.
