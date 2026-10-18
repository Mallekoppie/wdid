# wdid — Product & UI Design Plan

> **Status:** Draft for review · **Date:** 2026-10-17
>
> `wdid` ("what did I do") is a personal work ledger. It records where the time
> went, which major initiatives the work advanced, and who was supported along
> the way. It exists to make quarterly check-ins and performance reviews cheap:
> the data is captured continuously and exported in a form an AI can summarise.

---

## 1. Product summary

A **local-first** app for tracking work between check-ins, designed for **multi-user operation from day one** with a hosted deployment model as a first-class option.

**Core jobs**

1. Start a timer (or add an entry) in under five seconds and keep working.
2. Attribute every block of time to a **major initiative**, a **support activity**, or "other".
3. Record *outcomes and evidence*, not just hours, so reviews write themselves.
4. Produce a period summary ("since the last check-in") that can be handed to an AI,
   either as an export or through a built-in AI call.

**Non-goals for v1**

- Payroll, approvals, and invoicing workflows.
- Team-level billing or manager approval chains.
- Automatic activity capture (IDE/calendar/browser telemetry).
- Replacing a task tracker; initiatives are summarised, not decomposed into tickets.
- Any accountancy or operational workflow beyond a personal work journal.

**Deployment and scope**

The product is designed to be **local-first** for privacy and portability, while also
supporting a **hosted deployment** model for users who want centralized access,
backups, and shared infrastructure. It is built for **multi-user operation from the
start**, even if an individual developer uses it alone initially. That single-user
usage should not constrain the design, storage model, or access architecture.

The output is designed to be portable, review-friendly and easy to feed into a UI
builder such as `stitch.withgoogle.com` for quick dashboard prototyping. It is not
restricted to one person in the product design, even if the first live use case is a
single developer working on their own system.

**Success looks like**

- Fewer than 5 seconds to capture a thought or start a timer.
- A full quarter of work lives in one portable database plus readable exports.
- A check-in draft is generated in minutes, with concrete, verifiable bullets.
- Nothing is lost: scheduled backups exist and can be restored.

---

## 2. Domain model in plain language

| Concept | Meaning | Example |
| --- | --- | --- |
| **Initiative** | A major, named body of work that spans days or weeks and is worth reporting on. | "Migrate billing to the new pipeline" |
| **Work entry** | A block of time spent advancing an initiative (or "Other"). | 45 min on the billing migration |
| **Support entry** | Time spent helping someone else succeed. | 30 min reviewing Priya's design doc |
| **Check-in** | A saved marker with a start/end period, notes and a generated summary. | Q3 check-in, 2026-10-02 |
| **Period** | The range since the previous check-in (not necessarily a calendar quarter). | 2026-07-01 → 2026-10-02 |

An entry has **one** primary attribution: an initiative, a support activity, or
"other" (admin, meetings, unplanned). This keeps reporting unambiguous. Optional
tags provide secondary grouping.

---

## 3. Design principles

1. **Capture first, organise later — without losing category context.** The
   primary action is always visible and never behind a modal. When logging time,
   the user can either pick an existing category or create a new one inline in the
   same flow; the last-used category is remembered so the default path stays fast.
2. **One question per screen.** Today answers "what am I doing now?"; Log answers
   "what happened?"; Check-ins answer "what did I achieve?".
3. **Outcome over duration.** Every entry can carry a one-line result and links
   (PR, ticket, doc). That is what reviews need.
4. **Local-first, hosted-ready, and portable.** BoltDB is the source of truth for
   local deployments, while the architecture is designed to support hosted
   multi-user deployments without changing the core workflows. Exports remain plain
   Markdown/JSON/CSV.
5. **Quiet density.** A developer-tool aesthetic: compact rows, clear hierarchy,
   colour reserved for status and the running timer.
6. **Review-ready by default.** Every screen can answer "what would I tell my
   manager?" without extra data entry.

---

## 4. Information architecture

Persistent left navigation rail (labels always visible). A global header shows
the running timer and the check-in countdown on every screen.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│  wdid                        [ ▶ Billing migration  00:42:13 ]  [ Check-in ]│
├───────────┬──────────────────────────────────────────────────────────────────┤
│  Today    │                                                                  │
│  Log      │                                                                  │
│  Initiati…│                         screen content                           │
│  Support  │                                                                  │
│  Check-ins│                                                                  │
│           │                                                                  │
│  Settings │                                                                  │
└───────────┴──────────────────────────────────────────────────────────────────┘
```

| Route | Screen | Purpose |
| --- | --- | --- |
| `/today` | Today | Timer, quick capture, today's entries, day rollup |
| `/log` | Log | Search and edit entries across a period |
| `/initiatives` | Initiatives | Portfolio of major work, time invested, status |
| `/initiatives/:id` | Initiative detail | Entries, notes, milestones, progress |
| `/support` | Support | Log of helping others and its rollup |
| `/checkins` | Check-ins | List of past periods and drafted summaries |
| `/checkins/:id` | Check-in detail | Period report, AI summary, export |
| `/settings` | Settings | Data, backups, time rules, AI provider, appearance |

Global chrome:

- **Timer pill** — initiative name, elapsed time, pause/stop. Visible on all screens.
- **Check-in pill** — "23 days since last check-in" → opens `/checkins`.
- **Keyboard-first** — `T` start/stop timer, `N` new entry, `S` new support entry,
  `G` then `T/L/I/C` to navigate, `/` focus search.

---

## 5. Screen designs

### 5.1 Today (default screen)

```
┌─ Today · Fri 17 Oct ─────────────────────────────── 6h 15m this week ────────┐
│ ┌─ Running ────────────────────────────────────────────────────────────────┐ │
│ │  [Billing migration ▾]  Write the backfill script            00:42:13    │ │
│ │  [ Pause ]  [ Stop & save ]                              since 09:15     │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│ ┌─ Quick add ──────────────────────────────────────────────────────────────┐ │
│ │  What did you do?  [ .................... ]  [Initiative ▾]  [ 30m ] [+] │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│ Today                                                        4h 05m logged  │
│ ┌──────────────────────────────────────────────────────────────────────────┐ │
│ │ 09:15–09:57  Billing migration    Backfill script skeleton     42m  ⋮  │ │
│ │ 10:00–10:30  Support · Priya      Unblocked CI keys            30m  ⋮  │ │
│ │ 10:30–11:15  Billing migration    Reviewed migration plan      45m  ⋮  │ │
│ │ 11:15–12:00  Other · Meetings     Sprint planning              45m  ⋮  │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│ Week by initiative          ● Billing ████████████░░ 62%                     │
│                             ● Platform ████░░░░░░░░░░ 21%                    │
│                             ● Support  ███░░░░░░░░░░░ 17%                    │
│                                                                              │
│ [ End of day note ]                                     [ Log support ]     │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Components**

- **Timer card** — initiative selector (searchable, remembers the last used),
  free-text "what are you doing", elapsed clock, pause/resume, stop & save.
  Starting with no initiative selected prompts inline, never a modal.
- **Quick add** — one line, attribution selector, duration chip (15/30/45/60/custom),
  `Enter` saves. If started < 5 min ago, offers "start a timer instead".
- **Today list** — chronological, editable inline, row menu: edit, split, move,
  copy, delete. A support row is visually distinct (icon + muted accent).
- **Week bars** — share of logged time per initiative for the current week.
- **End of day note** — optional free text saved as a journal note against the date.

**States**

- No entries: centred "Nothing logged yet — start a timer or add an entry."
- Running: timer card is accent-tinted; tab title shows elapsed time.
- Forgot to stop: on return after the maximum block (default 4 h), prompt
  "Still working on Billing migration?" with Keep / Trim / Discard.

### 5.2 Log

Purpose: find, correct and export what happened.

```
┌─ Log ────────────────────────────────────────────────────────────────────────┐
│ [ 01 Jul – 17 Oct ▾ ]  [All initiatives ▾]  [All types ▾]  [ 🔍 search… ]   │
│                                                        4h 05m · 3 days shown │
│ ── Fri 17 Oct ─────────────────────────────────────────────── 4h 05m ─────── │
│  09:15–09:57  Billing migration   Backfill script skeleton     42m   ⋮     │
│  10:00–10:30  Support · Priya     Unblocked CI keys            30m   ⋮     │
│ ── Thu 16 Oct ─────────────────────────────────────────────── 6h 20m ─────── │
│  …                                                                          │
│                                                                              │
│ [ Export period ]                                       [ Add entry ]        │
└──────────────────────────────────────────────────────────────────────────────┘
```

- Grouped by local day, with a day total and a running period total.
- Filters: date range presets (Today, This week, Since last check-in, Quarter,
  Custom), initiative, type, tag, text.
- Inline editing of description, attribution, times and outcomes.
- Row detail expands to show outcome, links, tags and notes.
- Export action opens the same bundle used by check-ins (Markdown/JSON/CSV).

### 5.3 Initiatives

Portfolio view: one card per initiative, sorted by recent activity.

```
┌─ Initiatives ─────────────────────────────────────────────── [ + New ] ─────┐
│ ┌────────────────────────────┐  ┌────────────────────────────┐              │
│ │ Billing migration     Active│  │ Platform hardening  Planned│              │
│ │ ─────────────────────────  │  │ ─────────────────────────  │              │
│ │ 38h 20m this quarter       │  │ 4h 10m this quarter        │              │
│ │ ████████████░░░░ 64%       │  │ ██░░░░░░░░░░░░░░ 12%       │              │
│ │ Target: cut invoice time   │  │ Target: zero P1s from deps │              │
│ │ Last: backfill script · 2d │  │ Last: spike · 9d           │              │
│ └────────────────────────────┘  └────────────────────────────┘              │
│ ┌─ Archived (2) ───────────────────────────────────────────────────────────┐ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Fields shown:** name, status (`Planned · Active · Blocked · Done · Archived`),
time invested in the current period, progress (manual % + rationale), target
outcome, last activity, links.

**Detail screen**

- Header: name, status, time invested, progress slider, target outcome.
- Tabs: **Timeline** (entries), **Notes** (running log / decisions),
  **Milestones** (checklist with dates), **Report** (initiative-level summary
  the AI can reuse).
- `Log time` and `Add note` are always visible.
- Archived initiatives are read-only unless restored.

### 5.4 Support

A focused log of helping others — the thing reviews routinely forget.

```
┌─ Support ───────────────────────────────────────────────────────────────────┐
│ This quarter: 14h 30m · 9 people · 21 interactions      [ + Log support ]   │
│                                                                              │
│ By mode        Review ██████ 42%   Unblock ████ 28%   Pair ██ 18%  Other 12% │
│ By person      Priya 4h 10m · Sam 3h 25m · Jo 2h 05m · 4 others              │
│                                                                              │
│ ── Fri 17 Oct ────────────────────────────────────────────────────────────── │
│  Priya · Review   Design doc for the event bus   30m   Outcome: 3 risks noted│
│  ── Last week ────────────────────────────────────────────────────────────── │
│  Sam · Unblock    CI keys and service account    45m   Outcome: pipeline green│
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Quick form fields:** person, team (optional), mode
  (`Review · Pair · Unblock · Mentor · Incident · Other`), duration,
  what you did, impact/outcome, links.
- Rollups by mode, person and period. This rollup is a first-class section of
  the check-in report.
- Support entries may optionally reference an initiative (e.g. unblocking work
  on your own initiative), but remain a separate type.

### 5.5 Check-ins

**List** — each row: period, date, days covered, hours logged, initiatives
touched, summary state (`Draft · Generated · Edited · Final`).

**Create flow**

1. Period is prefilled from the last check-in's end date (or the period start
   configured in Settings) to today. Editable.
2. Optional "focus notes" free text: what mattered this period.
3. `Create check-in` snapshots aggregates and opens the detail screen.

**Detail**

```
┌─ Check-in · 01 Jul → 02 Oct 2026 ────────────────────────── [ Export ▾ ] ───┐
│ 213h logged · 6 initiatives · 21 support interactions · 14h support         │
│                                                                              │
│ ┌─ Summary ────────────────────────────────────────────────────────────────┐ │
│ │ [ Generate with AI ]  [ Copy prompt ]  [ Edit ]          model: …        │ │
│ │                                                                          │ │
│ │ ## Highlights                                                            │ │
│ │ - Cut invoice generation from 40 min to 3 min …                          │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│ ┌─ Time allocation ─────────┐ ┌─ Initiative progress ──────────────────────┐ │
│ │ Billing 38h 20m  64%      │ │ Billing migration        Active  64%       │ │
│ │ Platform 22h 10m 21%      │ │ Dependency upgrades      Done    100%      │ │
│ │ Support 14h 30m  17%      │ │ …                                          │ │
│ └───────────────────────────┘ └────────────────────────────────────────────┘ │
│ ┌─ Support & collaboration ────────────────────────────────────────────────┐ │
│ │ Priya — design review, 4h 10m, 6 interactions …                          │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│ [ Mark as final ]                       [ Export summary.md + data.json ]    │
└──────────────────────────────────────────────────────────────────────────────┘
```

- The summary is editable Markdown; generation never overwrites manual edits
  without confirmation.
- `Final` check-ins are read-only and become the boundary for the next period.
- Export produces the same AI bundle described in §8.

### 5.6 Settings

Grouped cards, no tabs:

- **Data** — database path (read-only display), data directory, backup directory,
  backup interval, retention count, `Backup now`, `Restore…`, `Export all data`.
  Shows last backup time and size, with a warning if overdue.
- **Time** — timezone, week start, daily target hours, rounding (none/5/15 min),
  long-running timer prompt threshold, default entry duration.
- **AI** — provider (`OpenAI-compatible`), base URL, model name, API key source
  (`environment variable` recommended, or stored), redaction of link URLs,
  prompt template preview and reset.
- **Appearance** — theme selector with multiple options (`System`, `Light`, `Dark`, `High Contrast`), density (Comfortable/Compact), and a preview swatch for each mode.
- **About** — version, schema version, license.

---

## 6. Visual design system

Follows the ChaosGenerator template's Flutter Material 3 approach, but with its
own identity. **Desktop-first**, responsive down to tablet; a phone layout is out
of scope for v1.

| Token | Value |
| --- | --- |
| Framework | Flutter web, Material 3, `useMaterial3: true` |
| Seed colour | **Deep Teal** (`#00696D`) — one seed, generated light and dark ramps |
| Default theme | System (light fallback) |
| Theme options | System, Light, Dark, High Contrast |
| Error / destructive | M3 `colorScheme.error` |
| Running / active | primary container + 2 px accent left border |
| Support entries | tertiary container tint (distinct from initiatives) |
| Warning (backup overdue) | M3 tertiary/amber container |
| Corner radius | 12 px cards, 8 px inputs, 28 px FAB |
| Density | Comfortable by default; Compact reduces row height 48 → 36 px |
| Type | Platform UI font; **tabular figures** (`FontFeature.tabularFigures`) for all times and durations |
| Icons | Material Symbols outlined; `timer`, `play_arrow`, `pause`, `stop`, `flag`, `volunteer_activism`, `event`, `history`, `insights`, `backup`, `settings` |

**Component vocabulary**

- Navigation rail with labels; selected item uses a filled tonal indicator.
- Cards/panels for the timer, quick add and chart sections.
- Dense data list (not a DataTable) with sticky day headers for the Log.
- Inline-edit rows; row overflow menu for destructive actions.
- Dialogs only for create/edit forms and destructive confirmations.
- Snackbars for save/delete/backup feedback.
- Empty states with one primary action.
- Skeletons or a centred spinner during initial load.

**Accessibility**

- All colour pairs meet WCAG AA; timer state is also conveyed by icon and text.
- Full keyboard operation; visible focus rings.
- Duration and dates always rendered in tabular numerals with ISO-like order.

---

## 7. Data model and BoltDB layout

Storage uses the goslow platform BoltDB helpers
(`platform.Database.BoltDb.SaveObject / ReadAllObjects / RemoveObject`) with JSON
values. One bucket per entity, plus index buckets maintained by the repository
layer.

### 7.1 Entities

**Initiative**

```json
{
  "id": "018f2c…",              // UUIDv7, lexicographically sortable
  "name": "Billing migration",
  "summary": "Move invoicing to the new pipeline",
  "targetOutcome": "Invoice generation under 5 minutes",
  "status": "active",           // planned | active | blocked | done | archived
  "progress": 64,               // 0-100, manual
  "startedAt": "2026-07-04T09:00:00Z",
  "targetDate": "2026-11-30",
  "links": [{"label": "Epic", "url": "…"}],
  "tags": ["billing"],
  "createdAt": "…", "updatedAt": "…"
}
```

**WorkItem**

```json
{
  "id": "018f2d…",
  "type": "initiative",         // initiative | category
  "initiativeId": "018f2c…",    // optional; set when the item belongs to a named initiative
  "category": "code-review",     // e.g. product-work | support | review | meetings | admin | learning | unplanned
  "categoryLabel": "PR reviews",
  "startedAt": "2026-10-17T07:15:00Z",
  "endedAt": "2026-10-17T07:57:00Z",
  "minutes": 42,
  "localDate": "2026-10-17",    // grouping day in the configured timezone
  "summary": "Backfill script skeleton",
  "outcome": "Script runs against staging",
  "notes": "",
  "links": [{"label": "PR #412", "url": "…"}],
  "tags": ["migration"],
  "person": null,                // optional; only used for category-based support/review work
  "team": null,
  "source": "timer",            // timer | manual
  "createdAt": "…", "updatedAt": "…"
}
```

This makes the model intentionally simple:

- **initiative work** → `type = "initiative"` and `initiativeId` is set
- **category work** → `type = "category"` and `initiativeId` is null; the
  category describes the work, such as `PR reviews`, `peer design reviews`,
  `support`, `meetings`, `feedback`, or `admin`
- The same structure is used for both, with initiative-based and category-based
  entries stored in the same bucket.

**CheckIn**

```json
{
  "id": "018f30…",
  "periodStart": "2026-07-01",
  "periodEnd": "2026-10-02",
  "createdAt": "…",
  "state": "draft",             // draft | generated | edited | final
  "focusNotes": "…",
  "summaryMarkdown": "…",
  "summaryModel": "…",
  "promptVersion": "v1",
  "totals": {"minutes": 12780, "byInitiative": {}, "byCategory": {}}
}
```

**Note** — initiative journal note or dated day note:
`{id, date, initiativeId?, text, createdAt}`.

**Settings** — single object: timezone, week start, daily target, rounding,
backup dir/interval/retention, AI provider/model/base URL, theme, density,
long-timer threshold, prompt version.

### 7.2 Buckets

| Bucket | Key | Value |
| --- | --- | --- |
| `meta` | `schema_version`, `instance_id` | scalar |
| `initiatives` | initiative id | Initiative JSON |
| `work_items` | work item id | WorkItem JSON |
| `notes` | note id | Note JSON |
| `checkins` | checkin id | CheckIn JSON |
| `settings` | `app` | Settings JSON |
| `idx_workitems_day` | `YYYY-MM-DD/<id>` | work item id |
| `idx_workitems_initiative` | `<initiativeId>/<id>` | work item id |
| `idx_workitems_category` | `<category>/<id>` | work item id |
| `idx_workitems_person` | `<person>/<id>` | work item id |

Indexes are written in the same operation as the entity and rebuilt on startup
if `meta.index_version` changes. Reads that need aggregation can also scan the
small buckets directly; the indexes exist for date-range and per-person queries.

**Rules**

- Timestamps stored in UTC (RFC 3339). `localDate` and day grouping derive from
  the configured timezone at write time.
- `minutes` is authoritative for reporting; `endedAt - startedAt` is the source
  when creating/editing, and round-trips.
- Entries may not overlap in the timer flow; manual entries may overlap and are
  flagged (not blocked) in the Log.
- IDs are UUIDv7 so bucket scans are chronological by key.

---

## 8. AI-ready export format

The goal is a **stable, self-describing bundle** that any AI can read without
extra instructions, plus a human-readable summary. Available from the Log, an
initiative and a check-in.

### 8.1 Bundle layout

```
wdid-export-2026-07-01_2026-10-02/
├── summary.md        # narrative + aggregates, prompt-ready
├── data.json         # complete structured data for the period
├── entries.csv       # flat work entries (spreadsheet friendly)
└── support.csv       # flat support entries
```

Exports are generated on demand and never written into the database directory.

### 8.2 `summary.md` contract

Fixed headings, ISO dates, explicit units. Order matters for repeatability.

```markdown
# wdid work report — 2026-07-01 to 2026-10-02

## Context
Role: <from settings, optional>
Period: 94 days · 213h 00m logged · 6 initiatives · 21 support interactions

## Time allocation
| Initiative | Hours | Share |
| --- | --- | --- |
| Billing migration | 38h 20m | 18% |
...
| Other (meetings, admin) | 41h 10m | 19% |

**Support:** 14h 30m (6.8%) across 9 people.

## Initiative progress
### Billing migration — Active, 64%
- Target outcome: …
- This period: 38h 20m, 34 entries
- Key outcomes:
  - Backfill script shipped (PR #412)
  - Migration plan reviewed
- Risks: …

## Support and collaboration
### Priya (Payments) — 4h 10m, 6 interactions
- Review: event bus design — 3 risks identified before implementation
...

## Weekly rhythm
| Week starting | Hours | Top initiative |
...

## Notes and context
- Focus notes from the check-in
- Day notes (newest first)

## Source data
Structured data: data.json · Flat entries: entries.csv · Support: support.csv
```

`data.json` mirrors the above: `{ "generatedAt", "period", "settingsSummary",
"initiatives": [...], "entries": [...], "support": [...], "notes": [...],
"totals": {...} }`, with `schemaVersion` and stable field names.

### 8.3 Prompt template (built-in AI and "Copy prompt")

The export UI offers **Copy prompt** which copies `summary.md` preceded by this
instruction block:

```
You are summarising a software engineer's work for a performance check-in.

Use only the data provided. Do not invent achievements, metrics or names.
Produce:
1. Five to seven highlight bullets, each with a measurable outcome.
2. One short paragraph per initiative: progress, impact, evidence.
3. A collaboration paragraph covering who was supported and how.
4. Time allocation observations (where the time went, and any imbalance).
5. Risks or gaps worth discussing.
6. Three ready-to-paste performance-review bullets in first person.

Style: concise, factual, no self-congratulation, no filler.
Output Markdown. Cite links only when they are present in the data.
```

### 8.4 Built-in AI generation

- Provider abstraction with one implementation: OpenAI-compatible
  `POST {baseURL}/chat/completions`, streaming.
- Key resolution order: environment variable → stored setting; the key is never
  included in exports or logs.
- Only the selected period is sent. A settings toggle can strip URLs and notes.
- Response is streamed into the editable summary box, then persisted on the
  check-in with model name and prompt version.
- Failures are explicit and non-destructive: the existing summary is untouched,
  with a retry action.

### 8.5 Stitch-ready output for UI prototyping

This is the next practical milestone after the base data model: produce a clean,
portable export that can be ingested by a UI builder such as
`stitch.withgoogle.com` to create a personal dashboard or visual reporting UI.

**Scope**

- Single-user only; no team timesheets, approvals, payroll, or invoicing.
- Personal work journal for a developer or operator.
- UI-first output for quick exploration, not accounting-grade compliance.

**Recommended export contract**

Create a file named `stitch-input.json` alongside the existing export bundle for a
selected period:

```json
{
  "schemaVersion": 1,
  "generatedAt": "2026-10-17T12:00:00Z",
  "person": "Alex",
  "period": {
    "start": "2026-07-01",
    "end": "2026-10-02"
  },
  "summary": {
    "totalMinutes": 12780,
    "initiativeMinutes": {"billing-migration": 2300, "platform": 1320},
    "supportMinutes": 870,
    "otherMinutes": 2460
  },
  "initiatives": [
    {
      "id": "billing-migration",
      "name": "Billing migration",
      "status": "active",
      "minutes": 2300,
      "progress": 64,
      "targetOutcome": "Invoice generation under 5 minutes"
    }
  ],
  "entries": [
    {
      "id": "018f2d…",
      "date": "2026-10-17",
      "initiativeId": "billing-migration",
      "type": "initiative",
      "summary": "Backfill script skeleton",
      "minutes": 42,
      "outcome": "Script runs against staging",
      "tags": ["migration"]
    }
  ],
  "support": [
    {
      "id": "018f2e…",
      "date": "2026-10-17",
      "person": "Priya",
      "mode": "review",
      "minutes": 30,
      "summary": "Reviewed event bus design",
      "impact": "3 risks identified before implementation"
    }
  ],
  "notes": [
    {
      "date": "2026-10-17",
      "text": "Backfill work is now stable enough to track by initiative."
    }
  ]
}
```

**Why this is the correct next step**

- It keeps the app's internal data model rich and stable.
- It gives a single, simple output format for UI experiments in Stitch.
- It avoids building expensive business workflows before proving the personal reporting loop.
- It keeps the prototype aligned with the actual goal: a private, review-ready work ledger.

**Stitch usage pattern**

- Upload the JSON as a static source or import through a simple connector.
- Build cards for total hours, initiative split, support time and recent activity.
- Add charts for weekly rhythm, progress by initiative and personal contribution patterns.
- Use the export as a design sandbox before committing to a deeper native UI.

This is intentionally not a team dashboard: no approvals, no payroll, no billing
logic, and no organisational accounting. It is simply a clean data source for a
private personal work overview.

---

## 9. Backend shape (following the ChaosGenerator template)

- Go module `mallekoppie/wdid`, built on `github.com/Mallekoppie/goslow`.
- `cmd/wdid/main.go` starts the goslow platform, repository layer and web server.
- `internal/contracts/*.proto` defines the gRPC services; gRPC-Web is served on
  the same origin as the embedded Flutter app.
- `web/` holds the Flutter web app; `cmd/wdid/dist/` is the embedded release build.
- A single container image runs the server; data lives on a mounted volume.

**Services (draft)**

| Service | RPCs |
| --- | --- |
| `TimerService` | `StartTimer`, `PauseTimer`, `ResumeTimer`, `StopTimer`, `GetActiveTimer` |
| `WorkItemService` | `ListWorkItems`, `GetWorkItem`, `CreateWorkItem`, `UpdateWorkItem`, `SplitWorkItem`, `DeleteWorkItem`, `GetWorkItemRollup` |
| `InitiativeService` | `ListInitiatives`, `GetInitiative`, `CreateInitiative`, `UpdateInitiative`, `ArchiveInitiative` |
| `CheckInService` | `ListCheckIns`, `CreateCheckIn`, `GetCheckIn`, `UpdateCheckIn`, `FinalizeCheckIn` |
| `SummaryService` | `BuildExport`, `DownloadExport`, `GenerateSummary` (stream) |
| `SettingsService` | `GetSettings`, `UpdateSettings`, `BackupNow`, `GetBackupStatus` |

Timer state is server-side (start timestamp + pause accumulator) so a browser
refresh or second tab does not lose it.

---

## 10. Backups and durability

- **Database:** `data/wdid.db` (BoltDB, `database.boltdb.filename` in the goslow
  platform config).
- **Backup directory:** configurable, default `backups/` next to the data dir.
- **Schedule:** on startup if the last backup is older than the interval
  (default 6 h), then at each interval while running; manual `Backup now`.
- **Mechanism:** `bolt.DB.View` + `tx.WriteTo(tmp)` to a temp file in the backup
  directory, `fsync`, then atomic rename to
  `wdid-YYYYMMDDTHHMMSSZ.db`. Never copy a live database file.
- **Verification:** open the new file read-only and read `meta.schema_version`
  before reporting success.
- **Retention:** keep the newest N (default 30) scheduled backups; never delete a
  manual backup automatically.
- **Restore:** stop writes, verify the chosen backup, move the current database
  to `wdid-before-restore-<timestamp>.db`, copy the backup into place, reopen,
  run index rebuild. Exposed in Settings and as `wdid backup|restore` CLI.
- **Schema migrations** run on startup inside a transaction and always trigger a
  pre-migration backup.

---

## 11. Key flows

1. **Start work** — Today → choose initiative (prefilled from last timer) → type
   what you're doing → Start. The timer pill appears everywhere.
2. **Switch work** — Timer pill → Stop & save (entry created) → choose the next
   initiative → Start. Optionally "Save and switch" in one step.
3. **Capture after the fact** — Quick add or `N`, duration chip, attribution,
   one-line summary; expand to add outcome/links.
4. **Log support** — `S` or `Log support` on Today → person, mode, duration,
   what you did, impact.
5. **Weekly tidy** — Log → "This week" → fix missing outcomes, split a long
   block, confirm initiatives.
6. **Check-in** — Check-ins → Create → confirm period → Generate with AI (or
   Copy prompt) → edit → Mark final → Export.
7. **Recovery** — Settings → Backups → choose a backup → Restore → confirm.

---

## 12. Milestones

| Milestone | Deliverable | Acceptance |
| --- | --- | --- |
| **M0 — Skeleton** | Dev container, Go module, goslow config, Makefile, Flutter web shell, proto generation | `make all`, `make test`, `make run` work in the container |
| **M1 — Data core** | Entities, repositories, indexes, migrations, settings | Round-trip tests for every bucket; index rebuild test |
| **M2 — Capture** | Timer service + global pill, Today screen, quick add, entry CRUD | Log a full day without touching the database directly |
| **M3 — Organise** | Log screen with filters and inline edit; Initiatives + detail | Quarter of historical data can be entered and corrected |
| **M4 — Support** | Support log, quick add, rollups | Support appears correctly in aggregates |
| **M5 — AI export** | `summary.md` / `data.json` / CSVs, Copy prompt, check-in create/detail | A pasted prompt produces a usable review draft |
| **M6 — Built-in AI** | Settings provider config, streaming generation, persistence | Generated summary saves on the check-in; failures are non-destructive |
| **M7 — Durability** | Scheduled backups, restore, retention, status UI | Restore from a backup in a test instance; overdue warning works |
| **M8 — Polish** | Dark theme, keyboard shortcuts, empty/error states, a11y pass | Keyboard-only check-in flow; AA contrast verified |

---

## 13. Risks and open decisions

- **Check-in cadence** — currently modelled as "since last check-in". Confirm
  whether a fixed quarter start is also needed for reports.
- **Rounding policy** — default is no rounding; confirm whether 5/15-minute
  rounding should be offered at all.
- **Overlapping manual entries** — currently flagged, not blocked. Confirm this
  is acceptable for backfilled calendars.
- **Storing the AI key** — environment variable is recommended; decide whether
  storing it in BoltDB (plaintext) is allowed at all.
- **Encryption of backups** — not in v1; confirm no requirement.
- **Single-user assumption** — no auth in v1. Confirm the server binds to
  localhost by default.
- **Support as a separate entity** — chosen for clean reporting. Confirm it
  should not simply be a tag on work entries.

---

## 14. Out of scope / future

- Calendar or issue-tracker imports (Jira, GitHub, Linear) to prefill entries.
- Mobile capture and a PWA install flow.
- Multi-user or shared initiatives.
- Export templates per organisation's review rubric.
- Charts beyond the weekly allocation bars (trend lines, heatmaps) in v2.
