# 19: Export bundle and copy prompt

**What to build:** A user can export a period or a check-in as a bundle containing `summary.md`, `data.json`, `entries.csv`, and `support.csv`, and can copy the AI prompt block with the summary. Exports are generated on demand and never written into the database directory.

**Blocked by:** 16 (Manager check-in create and finalize)

**Status:** ready-for-agent

- [ ] A period or check-in produces `summary.md`, `data.json`, `entries.csv`, and `support.csv`.
- [ ] The bundle is scoped to the selected period or check-in.
- [ ] `summary.md` follows the fixed headings, ISO dates, and units in the plan.
- [ ] `support.csv` contains person and mode columns; `entries.csv` is the flat work-entry sheet.
- [ ] Copy prompt yields the prompt block followed by `summary.md`.
- [ ] Exports are never written into the database directory.
- [ ] Connect and gRPC-Web tests cover bundle contents, period scoping, and prompt text.
