# 12: Project notes

**What to build:** A user can add, edit, and delete notes on a project, and can save an end-of-day note from Today. Notes provide context that the work entries alone do not capture.

**Blocked by:** 11 (Project detail: timeline and report)

**Status:** ready-for-agent

- [ ] A project note can be created, edited, and deleted from the project detail.
- [ ] The end-of-day note on Today is saved as a day note.
- [ ] Day notes and project notes use the same note model and survive a restart.
- [ ] Notes appear in the project detail in newest-first order.
- [ ] Loading, empty, error, and validation states are handled.
- [ ] Connect and gRPC-Web tests cover create, update, delete, and the two note contexts.
