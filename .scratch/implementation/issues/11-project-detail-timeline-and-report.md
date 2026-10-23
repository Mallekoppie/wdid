# 11: Project detail: timeline and report

**What to build:** Opening a project shows its header (category, status, progress, target outcome), its work-entry timeline, and a project-scoped report. The user can log time against the project from here.

**Blocked by:** 06 (Quick capture and today's list), 10 (Initiatives portfolio)

**Status:** ready-for-human

- [x] The project detail route opens from the portfolio and from a direct link.
- [x] The header shows category, status, progress, and target outcome.
- [x] The timeline lists the project's work entries newest first.
- [x] The report shows project-scoped totals and support interactions from that project's entries.
- [x] Log time creates an entry attributed to this project.
- [x] An archived project is read-only until restored.
- [x] Loading, empty, error, and validation states are handled.
- [x] Connect and gRPC-Web tests cover detail, timeline, report, and archived behaviour.

## Comments

- The service-backed detail is `ProjectDetailScreen`; the demo adapter keeps
  `InitiativeDetailScreen` until no screen needs the demo repository.
- Project totals come from `GetPeriodReport`; the support interaction list is
  filtered to the same period. No totals are composed from entry listings.
- `make check` passes, including the new unary and gRPC-Web project-detail test.
