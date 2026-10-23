# Glossary

The project's domain language. Terms here are canonical: use them exactly as
defined and do not drift to synonyms.

- **Work entry** (or **entry**) — a recorded block of work time in the ledger; the
  atomic unit the journal reports on. An entry is not a task or a ticket.

- **Category** — a user-defined top-level grouping of work. Every category has one
  reporting role, a name, an optional colour, a sort order, and an archived flag.

- **Subcategory** — the optional second level under a category. A subcategory
  never has children. Under an initiative-role category it is the project the user
  is working on.

- **Reporting role** — what a category means for reporting and validation:
  `initiative`, `support`, or `other`. The role is immutable and is independent of
  the category's name. Reports and validation use the role, never the name.

- **Initiative** — work whose category has the `initiative` role; typically a
  major body of work spanning days or weeks. The unit that carries status,
  progress, target outcome, and milestones is the subcategory beneath it.

- **Support** — work whose category has the `support` role: time spent helping
  another person succeed. Support is reported separately because reviews routinely
  omit it. A support entry requires a person; its mode is its subcategory, and its
  impact is its outcome.

- **Other** — work whose category has the `other` role: meetings, admin, learning,
  and unplanned work.

- **Check-in** — a saved artifact covering a period, with focus notes, aggregates,
  and an optional summary. Every check-in has a kind.

- **Manager check-in** — a check-in whose kind is `manager`. It answers "everything
  since we last spoke". Only a final manager check-in moves the boundary for the
  next manager check-in.

- **Personal review** — a check-in whose kind is `personal`. It is used for weekly
  or monthly self-review, never moves the manager boundary, and remains editable
  indefinitely.

- **Period** — the date range a check-in covers. A period is not necessarily a
  calendar quarter.

- **Milestone** — a dated checkpoint attached to a subcategory.

- **Note** — free text attached to a day or to a subcategory.
