# 05: Settings preferences end-to-end

**What to build:** A user can configure how wdid behaves: timezone, week start, daily target, default entry duration, long-timer threshold, personal-review cadence, theme, density, and the About information. Values persist per user and take effect immediately.

**Blocked by:** 03 (Category taxonomy data core)

**Status:** ready-for-agent

- [x] Time settings persist: timezone, week start, daily target, default duration, long-timer threshold, and review cadence.
- [x] Appearance settings persist and apply immediately: theme and density.
- [x] About shows version, schema version, and license.
- [x] Invalid enum values and out-of-range numbers are rejected with field errors.
- [x] Settings are per user and survive a service restart.
- [x] Connect and gRPC-Web tests cover get, update, validation, and isolation.
