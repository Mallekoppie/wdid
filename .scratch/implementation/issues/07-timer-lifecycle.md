# 07: Timer lifecycle end-to-end

**What to build:** A user can start a timer against a category and optional subcategory, pause and resume it, and stop it to save a work entry. Paused time is excluded, one timer runs per user, and the timer pill follows the user across screens. A timer that runs past the block limit asks whether to keep, trim, or discard the entry.

**Blocked by:** 04 (Category management end-to-end), 06 (Quick capture and today's list)

**Status:** ready-for-human

- [x] A timer starts, pauses, resumes, and stops; a user has at most one active timer.
- [x] Paused time is excluded from elapsed time.
- [x] Stopping saves a work entry with the selected category and optional subcategory.
- [x] A stop under one minute is rejected unless the action is discard.
- [x] Above the block limit, stopping offers keep, trim, or discard.
- [x] The timer pill is visible on every screen and survives a refresh or second tab.
- [x] Timer state is server-owned; the client only renders it.
- [x] Connect and gRPC-Web tests cover the transitions, the one-minute rule, and the block limit.

## Comments

- Implemented and committed in `b57394b` ("implement timer lifecycle end-to-end"), with the searchable category selector follow-up in `543c05f`; every box was ticked at implementation time.
- Bookkeeping reconciliation (2026-10-23): the issue file never received a Comments entry or the post-implementation status when the work landed, so both were added during a status sweep. No code changes were made during reconciliation.
