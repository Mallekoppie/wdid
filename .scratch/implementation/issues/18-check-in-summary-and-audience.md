# 18: Check-in summary editing and audience

**What to build:** A user can edit a check-in summary as Markdown, save it, and choose the audience for a manager check-in. Manual edits are never overwritten without confirmation, and the audience preset changes only the prompt, not the underlying data.

**Blocked by:** 16 (Manager check-in create and finalize)

**Status:** ready-for-agent

- [ ] The summary can be edited and saved as Markdown.
- [ ] A manager check-in can choose 1:1 or performance review as its audience.
- [ ] The audience preset is visible on the check-in and used when building the prompt.
- [ ] Manual edits are not overwritten without confirmation.
- [ ] An empty summary is allowed.
- [ ] Loading, empty, error, and validation states are handled.
- [ ] Connect and gRPC-Web tests cover save, audience selection, and overwrite protection.
