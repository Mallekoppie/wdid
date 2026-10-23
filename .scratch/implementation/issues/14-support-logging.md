# 14: Support logging

**What to build:** A user can log support work from the Support screen: who was helped, an optional team, the mode, the duration, what happened, and the outcome. A support entry cannot be saved without a person. Support rows are visually distinct from initiative work.

**Blocked by:** 04 (Category management end-to-end), 06 (Quick capture and today's list)

**Status:** ready-for-agent

- [ ] The support form captures person, optional team, mode, duration, description, outcome, and links.
- [ ] Saving without a person is rejected with a field error.
- [ ] Support modes come from the subcategories of the support-role category.
- [ ] The support feed lists entries newest first and marks support rows distinctly.
- [ ] Support work is not cross-attributed to a project.
- [ ] Loading, empty, error, and validation states are handled.
- [ ] Connect and gRPC-Web tests cover create, list, and the person-required rule.
