# wdid — Product & System Plan

> **Status:** Canonical. Revised 2026-10-23.
>
> **Authority:** This document is the source of product intent and the single
> design baseline for wdid. Where the current implementation disagrees with this
> plan, the implementation is wrong and must be migrated. The first implementation
> pass predates several decisions recorded here and is not authoritative.
>
> `wdid` ("what did I do") is a personal work ledger. It records where the time
> went, which work it advanced, and who was supported along the way, so that
> manager check-ins and performance reviews are cheap to produce.

---

## 1. Product summary

A **local-first** app for tracking work between check-ins, built for
**multi-user operation from day one** with a hosted deployment model as a
first-class option.

**Core jobs**

1. Start a timer or add an entry in under five seconds and keep working.
2. Attribute every block of time to a **category**, optionally narrowed to a
   **subcategory**, using a taxonomy each user configures.
3. Record *outcomes and evidence*, not just hours, so reviews write themselves.
4. Produce two different review artifacts from the same ledger:
   - a **manager check-in**: everything since the last check-in with the manager;
   - a **personal review**: a self-directed look at the last week or month, used
     to improve before the next manager check-in.

**Deployment and scope**

- Local-first: one binary, one BoltDB file, no external services required.
- Hosted: multi-user, authenticated, per-user data isolation.
- Portable: the database is one file and exports are plain Markdown, JSON, and
  CSV. Nothing depends on a SaaS provider.

**Success looks like**

- Fewer than five seconds to capture a thought or start a timer.
- A full quarter of work lives in one portable database plus readable exports.
- A manager check-in draft is generated in minutes, with concrete, verifiable
  bullets.
- A weekly personal review takes one sitting and changes what the user does next.
- Nothing is lost: scheduled backups exist and can be restored.

**Non-goals for v1**

- Payroll, approvals, invoicing, and manager sign-off workflows.
- Team timesheets or shared initiatives.
- Automatic activity capture (IDE, calendar, browser telemetry).
- Replacing a task tracker; initiatives are summarised, not decomposed into
  tickets.
- Accountancy or operational workflow beyond a personal work journal.

---

## 2. Domain model

The taxonomy is **two levels**: a user-defined **category**, optionally narrowed
by a **subcategory**. There is no third level.

| Concept | Meaning |
| --- | --- |
| **Category** | A user-defined top-level grouping of work. It has one fixed **reporting role**, a name, an optional colour, a sort order, and an archived flag. Examples: `Initiatives`, `Support`, `Other`. |
| **Reporting role** | What a category *means* for reporting and validation: `initiative`, `support`, or `other`. The role is independent of the category's name. |
| **Subcategory** | The optional second level under a category. Under an `initiative`-role category it is the project the user is working on and carries status, progress, target outcome, and milestones. |
| **Work entry** | A recorded block of work time with exactly one category, an optional subcategory from that category, a description, an outcome, start/end timestamps, and authoritative minutes. |
| **Support** | Work in a category whose role is `support`. It requires a person and is reported separately because reviews routinely omit it. Support modes (`Review`, `Pair`, `Unblock`, `Mentor`, `Incident`, `Other`) are seeded subcategories. |
| **Other** | Work in a category whose role is `other`: meetings, admin, learning, unplanned work. |
| **Check-in** | A saved artifact covering a period, with focus notes, aggregates, and an optional AI summary. It has one **kind**: `manager` or `personal`. |
| **Manager check-in** | A check-in that answers "everything since we last spoke". Only a **final** manager check-in moves the period boundary. |
| **Personal review** | A check-in used for weekly or monthly self-review. It never moves the manager boundary and remains editable. |
| **Period** | The date range a check-in covers. A period is not necessarily a calendar quarter. |
| **Milestone** | A dated checkpoint attached to a subcategory. |
| **Note** | Free text attached to a day or to a subcategory. |

**Rules**

- **One attribution.** Every work entry has exactly one category and at most one
  subcategory belonging to it. There is no second attribution.
- **Roles are fixed, names are not.** A category's role is chosen at creation and
  never changes. A user may rename `Initiatives` to `Projects` without breaking
  reporting.
- **Categories are per user.** Each account configures its own taxonomy. Categories
  and subcategories are archived, not deleted, once an entry references them.
- **Support requires a person.** An entry in a `support`-role category must name
  the person supported; team is optional. Support impact is the entry's outcome.
- **Initiative subcategories carry project fields.** Status, progress, target
  outcome, target date, links, and milestones are meaningful under an
  `initiative`-role category and are surfaced only there.
- **Minutes are authoritative.** Durations are stored in minutes; there is no
  rounding. Overlapping manual entries are allowed and flagged, never blocked.
- **Local dates are explicit.** Timestamps are stored in UTC; the grouping day is
  derived from the user's configured timezone at write time.
- **Identity is never client-supplied.** The owning user is always derived from
  the validated token.

---

## 3. Design principles

1. **Capture first, organise later — without losing context.** The primary action
   is always visible. When logging time the user can choose an existing category
   or create one inline; the last-used category and subcategory are remembered.
2. **One question per screen.** Today answers "what am I doing now?"; Log answers
   "what happened?"; Initiatives and Support answer "what did it advance and who
   did it help?"; Check-ins answer "what did I achieve?".
3. **Outcome over duration.** Every entry can carry a one-line outcome and links.
   That is what reviews need.
4. **Local-first, hosted-ready, portable.** BoltDB is the local source of truth;
   the same model runs hosted for multiple users. Exports remain plain
   Markdown/JSON/CSV.
5. **Quiet density.** A developer-tool aesthetic: compact rows, clear hierarchy,
   colour reserved for status and the running timer.
6. **Review-ready by default.** Every screen can answer "what would I tell my
   manager?" without extra data entry.
7. **The ledger does not lie.** Stored minutes are reported as recorded, overlaps
   are visible, and no setting silently rounds or rewrites history.

---

## 4. Identity, access, and tenancy

wdid is multi-user from day one. The local-first deployment is simply the
single-account case of the same architecture.

**Roles**

| Role | Scope |
| --- | --- |
| `admin` | Own workspace, plus instance-level backups, invite issuance, and identity configuration. |
| `user` | Own workspace only. No access to another user's categories, entries, notes, or check-ins. |

**Account creation**

1. The first account is created from a deployment-provided bootstrap secret and
   becomes `admin`.
2. Every later account requires a **single-use invite code** issued by an admin.
   The deployment secret is never used again after bootstrap.
3. In v1, invites are created through the CLI (`wdid invite create`). The
   Users & Access screen is deferred.

**Authentication**

- Local email + password, stored as a bcrypt hash separate from the profile, and
  a locally issued HS256 JWT.
- Optional Zitadel OIDC. When enabled, the same protected RPCs accept a Zitadel
  ID token. The first OIDC login provisions a local account by email; a
  configured role claim maps to `admin`.
- Local password login is the break-glass path. WebAuthn/passkeys are deferred.

**Tenancy**

Every user-owned record lives in a bucket prefixed with the user identifier.
Cross-account reads return not-found by construction; the service never trusts a
user or tenant identifier supplied in a request.

**Transport security**

- Exact CORS origins only; never a wildcard.
- Health enabled. Reflection enabled in development only.
- TLS required on non-loopback listeners.

---

## 5. Information architecture

Persistent left navigation rail with labels. A global header shows the running
timer and the time since the last final manager check-in.

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
| `/today` | Today | Timer, quick capture, today's entries, day rollup, review prompt |
| `/log` | Log | Search and edit entries across a period |
| `/initiatives` | Initiatives | Portfolio of subcategories under `initiative`-role categories |
| `/initiatives/:id` | Project detail | Timeline, notes, milestones, progress, report |
| `/support` | Support | Support log and rollups by person and mode |
| `/checkins` | Check-ins | Manager check-ins and personal reviews, filterable by kind |
| `/checkins/:id` | Check-in detail | Period report, AI summary, export, finalize |
| `/settings` | Settings | Categories, data/backups, exports, time, AI, appearance, about |
| `/login` | Login / registration | Local login, OIDC, invite-code registration |

Anything that is not a daily destination lives inside Settings: category
management, backups, export downloads, time rules, AI configuration, and
appearance. There are no separate Vault, Exports, Users, or OIDC routes in v1.

**Global chrome**

- **Timer pill** — category/subcategory name, elapsed time, pause/stop. Visible on
  every screen.
- **Check-in pill** — "23 days since last manager check-in" → opens `/checkins`.
- **Review prompt** — non-blocking "Last week is ready to review" when the
  personal-review cadence is on. It opens a live review; nothing is saved until
  the user saves it.

**Keyboard-first**

`T` start/stop timer, `N` new entry, `S` new support entry, `G` then `T/L/I/C` to
navigate, `/` focus search, `?` shortcut reference.

---

## 6. Screen designs

### 6.1 Today (default screen)

```
┌─ Today · Fri 17 Oct ─────────────────────────────── 6h 15m this week ────────┐
│ ┌─ Running ────────────────────────────────────────────────────────────────┐ │
│ │  [Initiatives ▾] [Billing migration ▾]  Write the backfill script  42:13 │ │
│ │  [ Pause ]  [ Stop & save ]                              since 09:15     │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│ ┌─ Quick add ──────────────────────────────────────────────────────────────┐ │
│ │  What did you do?  [ .................... ] [Category ▾] [Sub ▾] [ 30m ]+│ │
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
│ Week by category            Initiatives ████████████░░ 62%                    │
│                             Support     ███░░░░░░░░░░░ 17%                    │
│                             Other       ████░░░░░░░░░░ 21%                    │
│                                                                              │
│ [ End of day note ]                                     [ Log support ]     │
└──────────────────────────────────────────────────────────────────────────────┘
```

- **Timer card** — category and subcategory selectors (searchable, remembers the
  last used), free-text description, elapsed clock, pause/resume, stop & save.
  Starting without a category prompts inline, never in a modal.
- **Quick add** — one line, category/subcategory selectors, duration chip
  (15/30/45/60/custom), `Enter` saves. If the user started something less than
  five minutes ago, offer "start a timer instead".
- **Today list** — chronological, editable inline. Row menu: edit, split, move,
  copy, delete. Support rows are visually distinct.
- **Week bars** — share of logged time by category for the current week, with
  subcategory breakdown on hover or expand.
- **End of day note** — optional free text saved as a note against the date.
- **Review prompt** — appears once per cadence period when a personal review is
  due; dismissible.

**States**

- No entries: "Nothing logged yet — start a timer or add an entry."
- Running: the timer card is accent-tinted; the tab title shows elapsed time.
- Forgot to stop: after the block limit (default 4 h), prompt "Still working on
  Billing migration?" with Keep / Trim / Discard.
- Overdue backup: a warning in the header, linking to Settings.

### 6.2 Log

```
┌─ Log ────────────────────────────────────────────────────────────────────────┐
│ [ 01 Jul – 17 Oct ▾ ] [All categories ▾] [All subcategories ▾] [ 🔍 search… ]│
│                                                        4h 05m · 3 days shown │
│ ── Fri 17 Oct ─────────────────────────────────────────────── 4h 05m ─────── │
│  09:15–09:57  Initiatives · Billing   Backfill script skeleton   42m   ⋮   │
│  10:00–10:30  Support · Priya         Unblocked CI keys          30m   ⋮   │
│ ── Thu 16 Oct ─────────────────────────────────────────────── 6h 20m ─────── │
│  …                                                                          │
│                                                                              │
│ [ Export period ]                                       [ Add entry ]        │
└──────────────────────────────────────────────────────────────────────────────┘
```

- Grouped by local day, with a day total and a period total.
- Filters: date presets (`Today`, `This week`, `Last 7 days`, `This month`,
  `Since last manager check-in`, `Custom`), category, subcategory, text.
- Inline editing of description, category/subcategory, times, and outcomes.
- Row detail expands to show outcome, links, tags, and notes.
- Overlapping entries carry a visible overlap marker; they are never blocked.
- Export opens the same bundle used by check-ins.

### 6.3 Initiatives

A portfolio view over the subcategories of `initiative`-role categories.

```
┌─ Initiatives ─────────────────────────────────────────────── [ + New ] ─────┐
│ ┌────────────────────────────┐  ┌────────────────────────────┐              │
│ │ Billing migration     Active│  │ Platform hardening  Planned│              │
│ │ 38h 20m this quarter       │  │ 4h 10m this quarter        │              │
│ │ ████████████░░░░ 64%       │  │ ██░░░░░░░░░░░░░░ 12%       │              │
│ │ Target: cut invoice time   │  │ Target: zero P1s from deps │              │
│ │ Last: backfill script · 2d │  │ Last: spike · 9d           │              │
│ └────────────────────────────┘  └────────────────────────────┘              │
│ ┌─ Archived (2) ───────────────────────────────────────────────────────────┐ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────────┘
```

**Fields shown:** name, parent category, status (`Planned · Active · Blocked ·
Done · Archived`), time invested in the current period, progress, target outcome,
last activity, links.

**Detail screen**

- Header: name, category, status, time invested, progress, target outcome.
- Tabs: **Timeline** (entries), **Notes** (running log / decisions),
  **Milestones** (checklist with dates), **Report** (project-level summary).
- `Log time` and `Add note` are always visible.
- Archived projects are read-only unless restored.

### 6.4 Support

A focused log of helping others, and its rollups.

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

- **Quick form fields:** person, team (optional), subcategory (support mode),
  duration, what you did, outcome, links.
- Rollups by mode, person, and period. This rollup is a first-class section of
  the manager check-in.
- An entry belongs to one category. Support work is not cross-attributed to an
  initiative; when the link matters, record it in the description or outcome.
- Support entries require a person; the form will not save without one.

### 6.5 Check-ins

**List** — one list with a kind filter (`All`, `Manager`, `Personal`). Each row
shows period, kind, days covered, hours logged, categories touched, and state
(`Draft · Generated · Edited · Final`). Personal reviews have no `Final` state.

**Create a manager check-in**

1. The period is prefilled from the end of the last **final manager check-in**
   (or the journal start date) to today. It is editable.
2. Optional focus notes: what mattered this period.
3. `Create manager check-in` snapshots the aggregates and opens the detail
   screen.

**Create a personal review**

1. Choose a timeframe: `Last 7 days`, `Last 30 days`, `This week`, `This month`,
   `Since last manager check-in`, or `Custom range`.
2. The review opens live with the same aggregates and summary tools as a manager
   check-in.
3. It is saved only when the user chooses `Save review`. Leaving without saving
   discards it.

**Detail**

```
┌─ Manager check-in · 01 Jul → 02 Oct 2026 ───────────────── [ Export ▾ ] ────┐
│ 213h logged · 6 projects · 21 support interactions · 14h support             │
│                                                                              │
│ ┌─ Summary ────────────────────────────────────────────────────────────────┐ │
│ │ [ Generate with AI ] [ Copy prompt ] [ Edit ]     audience: 1:1 ▾        │ │
│ │                                                                          │ │
│ │ ## Highlights                                                            │ │
│ │ - Cut invoice generation from 40 min to 3 min …                          │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│ ┌─ Time allocation ─────────┐ ┌─ Initiative progress ──────────────────────┐ │
│ │ Initiatives 38h 20m  64%  │ │ Billing migration        Active  64%       │ │
│ │ Support     14h 30m  17%  │ │ Dependency upgrades      Done    100%      │ │
│ │ Other       22h 10m  19%  │ │ …                                          │ │
│ └───────────────────────────┘ └────────────────────────────────────────────┘ │
│ ┌─ Support & collaboration ────────────────────────────────────────────────┐ │
│ │ Priya — design review, 4h 10m, 6 interactions …                          │ │
│ └──────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│ [ Mark as final ]                       [ Export summary.md + data.json ]    │
└──────────────────────────────────────────────────────────────────────────────┘
```

- The summary is editable Markdown. Generation never overwrites manual edits
  without confirmation.
- **Audience** (manager check-ins only): `1:1` (default) or `Performance review`.
  It selects the prompt variant; it does not change the data.
- `Final` manager check-ins are read-only and become the boundary for the next
  manager period.
- Personal reviews remain editable indefinitely and never change the boundary. A
  saved personal review may be deleted; a final manager check-in may not.
- Export produces the bundle described in §9.

### 6.6 Settings

Grouped cards, no tabs:

- **Categories** — the user's taxonomy. Each category shows its reporting role,
  colour, sort order, archived state, and subcategories. Roles are chosen at
  creation and cannot be changed. Referenced categories are archived, not deleted.
  Seeded defaults are described in §8.4.
- **Data & backups** — database path (read-only), data directory, backup
  directory, backup interval, retention count, `Backup now`, `Restore…`,
  `Export all data`. Shows last backup time and size, with an overdue warning.
- **Exports** — period picker and the bundle download. The same export is
  available inline from Log and Check-in detail.
- **Time** — timezone, week start, daily target hours, long-running timer prompt
  threshold, default entry duration, personal-review cadence
  (`Weekly` / `Monthly` / `Off`). There is no rounding setting.
- **AI** — provider (`OpenAI-compatible`), base URL, model name, key source
  (environment variable only), redaction of URLs and notes, prompt template
  preview and reset.
- **Appearance** — theme (`System`, `Light`, `Dark`, `High Contrast`), density
  (`Comfortable` / `Compact`), preview swatches.
- **About** — version, schema version, license.

### 6.7 Login and registration

- Local email + password login.
- Zitadel button when OIDC is enabled.
- Registration requires an invite code; the first account uses the deployment
  bootstrap secret.
- Local password login is the break-glass path. No passkey credential in v1.

---

## 7. Visual design system

Desktop-first, responsive down to tablet; a phone layout is out of scope for v1.

| Token | Value |
| --- | --- |
| Framework | Flutter web, Material 3, `useMaterial3: true` |
| Seed colour | **Deep Teal** (`#00696D`) — one seed, generated light and dark ramps |
| Default theme | System (light fallback) |
| Theme options | System, Light, Dark, High Contrast |
| Error / destructive | M3 `colorScheme.error` |
| Running / active | primary container + 2 px accent left border |
| Support entries | tertiary container tint (distinct from initiative work) |
| Warning (backup overdue) | M3 tertiary/amber container |
| Corner radius | 12 px cards, 8 px inputs, 28 px FAB |
| Density | Comfortable by default; Compact reduces row height 48 → 36 px |
| Type | Platform UI font; **tabular figures** for all times and durations |
| Icons | Material Symbols outlined; `timer`, `play_arrow`, `pause`, `stop`, `flag`, `volunteer_activism`, `event`, `history`, `insights`, `backup`, `settings` |

**Component vocabulary**

- Navigation rail with labels; selected item uses a filled tonal indicator.
- Cards/panels for the timer, quick add, and chart sections.
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

## 8. Data model and storage

Storage uses BoltDB through the goslow platform helpers, with JSON values. One
bucket per entity, plus index buckets maintained by the repository layer.

### 8.1 Entities

**Category**

```json
{
  "id": "018f2c…",
  "userId": "018f20…",
  "name": "Initiatives",
  "role": "initiative",
  "color": "#00696D",
  "sortOrder": 0,
  "archived": false,
  "createdAt": "2026-10-23T08:00:00Z",
  "updatedAt": "2026-10-23T08:00:00Z"
}
```

`role` is one of `initiative`, `support`, `other` and is immutable after
creation.

**Subcategory**

```json
{
  "id": "018f2d…",
  "userId": "018f20…",
  "categoryId": "018f2c…",
  "name": "Billing migration",
  "description": "Move invoicing to the new pipeline",
  "status": "active",
  "progress": 64,
  "targetOutcome": "Invoice generation under 5 minutes",
  "targetDate": "2026-11-30",
  "links": [{"label": "Epic", "url": "…"}],
  "sortOrder": 0,
  "archived": false,
  "createdAt": "2026-10-23T08:00:00Z",
  "updatedAt": "2026-10-23T08:00:00Z"
}
```

Project fields are optional. They are surfaced in the UI only when the parent
category's role is `initiative`.

**Work entry**

```json
{
  "id": "018f2e…",
  "userId": "018f20…",
  "categoryId": "018f2c…",
  "subcategoryId": "018f2d…",
  "description": "Backfill script skeleton",
  "outcome": "Script runs against staging",
  "startedAt": "2026-10-17T07:15:00Z",
  "endedAt": "2026-10-17T07:57:00Z",
  "minutes": 42,
  "localDate": "2026-10-17",
  "person": null,
  "team": null,
  "tags": ["migration"],
  "links": [{"label": "PR #412", "url": "…"}],
  "source": "timer",
  "createdAt": "2026-10-17T07:57:00Z",
  "updatedAt": "2026-10-17T07:57:00Z"
}
```

- `categoryId` is required. `subcategoryId` is optional and must belong to the
  category.
- `person` is required when the category's role is `support`, and optional
  otherwise.
- `source` is `timer` or `manual`.
- `minutes` is authoritative. `endedAt - startedAt` is the source when creating or
  editing, and the two round-trip.

**Milestone**

```json
{
  "id": "018f2f…",
  "userId": "018f20…",
  "subcategoryId": "018f2d…",
  "title": "Ship backfill to staging",
  "dueDate": "2026-10-31",
  "done": false,
  "createdAt": "2026-10-23T08:00:00Z",
  "updatedAt": "2026-10-23T08:00:00Z"
}
```

**Note**

```json
{
  "id": "018f30…",
  "userId": "018f20…",
  "date": "2026-10-17",
  "subcategoryId": null,
  "text": "Backfill work is stable enough to track by project.",
  "createdAt": "2026-10-17T18:00:00Z"
}
```

A note has a `date`, a `subcategoryId`, or both.

**Check-in**

```json
{
  "id": "018f31…",
  "userId": "018f20…",
  "kind": "manager",
  "periodStart": "2026-07-01",
  "periodEnd": "2026-10-02",
  "state": "draft",
  "audience": "one_on_one",
  "focusNotes": "…",
  "summaryMarkdown": "…",
  "summaryModel": "…",
  "promptVersion": "v1",
  "totals": {
    "minutes": 12780,
    "byCategory": {"Initiatives": 2300, "Support": 870, "Other": 2460},
    "bySubcategory": {"Billing migration": 2300},
    "supportByPerson": {"Priya": 250}
  },
  "createdAt": "2026-10-02T17:00:00Z",
  "updatedAt": "2026-10-02T17:00:00Z"
}
```

- `kind` is `manager` or `personal`.
- `state` is `draft`, `generated`, `edited`, or `final`. `final` is valid only
  for manager check-ins.
- `audience` is `one_on_one` or `performance_review`, and only applies to manager
  check-ins.
- `totals` is a snapshot taken when the check-in is created; it is not recomputed
  when older entries change.

**Settings**

One object per user: timezone, week start, daily target minutes, review cadence,
long-timer threshold, default duration, backup directory/interval/retention, AI
base URL/model/redaction flag, theme, density, and journal start date. The AI key
is never stored.

### 8.2 Buckets

| Bucket | Key | Value |
| --- | --- | --- |
| `sys:meta` | `schema_version`, `instance_id` | scalar |
| `sys:users` | user id | user profile |
| `sys:user_emails` | lower-cased email | user id |
| `sys:user_credentials` | user id | bcrypt hash |
| `sys:invites` | invite code hash | invite record |
| `user_<id>:categories` | category id | Category JSON |
| `user_<id>:subcategories` | subcategory id | Subcategory JSON |
| `user_<id>:entries` | entry id | Work entry JSON |
| `user_<id>:milestones` | milestone id | Milestone JSON |
| `user_<id>:notes` | note id | Note JSON |
| `user_<id>:checkins` | check-in id | Check-in JSON |
| `user_<id>:settings` | `app` | Settings JSON |
| `user_<id>:timer` | `active` | Timer JSON |
| `user_<id>:idx_entries_day` | `YYYY-MM-DD/<id>` | entry id |
| `user_<id>:idx_entries_category` | `<categoryId>/<id>` | entry id |
| `user_<id>:idx_entries_subcategory` | `<subcategoryId>/<id>` | entry id |
| `user_<id>:idx_entries_person` | `<person>/<id>` | entry id |

Indexes are written in the same operation as the entity and rebuilt on startup
when the index version changes. Date-range and per-person queries use the
indexes; small buckets may be scanned directly.

### 8.3 Invariants

- IDs are UUIDv7 so bucket scans are chronological by key.
- Timestamps are stored in UTC (RFC 3339). `localDate` is derived from the
  configured timezone at write time.
- Entries may not overlap in the timer flow; manual entries may overlap and are
  flagged in the Log.
- One active timer per user. Paused time is excluded from elapsed time.
- A stop under one minute is rejected unless the action is `discard`.
- Above the block limit, stopping returns a conflict until the caller chooses
  `keep`, `trim`, or `discard`.
- A category role cannot change. A category or subcategory referenced by an entry
  can be renamed and archived, but not deleted.
- Cross-account reads return not-found by construction.

### 8.4 Seed data

Every new account receives:

- `Initiatives` (`initiative`) with no subcategories.
- `Support` (`support`) with subcategories `Review`, `Pair`, `Unblock`, `Mentor`,
  `Incident`, `Other`.
- `Other` (`other`) with subcategories `Meetings`, `Admin`, `Learning`,
  `Unplanned`.

Seeds are ordinary user-owned categories: they can be renamed, extended, and
archived. No code may special-case a category by name; reporting uses the role.

---

## 9. AI-ready export format

The export is a stable, self-describing bundle that any AI or spreadsheet can
read, plus a human-readable summary. It is available from the Log, a project, and
a check-in.

### 9.1 Bundle layout

```
wdid-export-2026-07-01_2026-10-02/
├── summary.md        # narrative + aggregates, prompt-ready
├── data.json         # complete structured data for the period
├── entries.csv       # flat work entries
└── support.csv       # flat support entries
```

Exports are generated on demand and never written into the database directory.
There is no UI-builder-specific export.

### 9.2 `summary.md` contract

Fixed headings, ISO dates, explicit units. Order matters for repeatability.

```markdown
# wdid work report — 2026-07-01 to 2026-10-02

## Context
Role: <from settings, optional>
Period: 94 days · 213h 00m logged · 6 projects · 21 support interactions

## Time allocation
| Category | Hours | Share |
| --- | --- | --- |
| Initiatives | 38h 20m | 18% |
| Support | 14h 30m | 7% |
| Other | 41h 10m | 19% |
...

### Initiatives
| Project | Hours | Share |
| --- | --- | --- |
| Billing migration | 23h 00m | 11% |
...

## Initiative progress
### Billing migration — Active, 64%
- Target outcome: …
- This period: 38h 20m, 34 entries
- Milestones: 2 of 5 complete
- Key outcomes:
  - Backfill script shipped (PR #412)
  - Migration plan reviewed
- Risks: …

## Support and collaboration
### Priya (Payments) — 4h 10m, 6 interactions
- Review: event bus design — 3 risks identified before implementation
...

## Weekly rhythm
| Week starting | Hours | Top category |
...

## Notes and context
- Focus notes from the check-in
- Day notes and project notes (newest first)

## Source data
Structured data: data.json · Flat entries: entries.csv · Support: support.csv
```

`data.json` mirrors the above: `{ "schemaVersion", "generatedAt", "period",
"settingsSummary", "categories": [...], "subcategories": [...], "entries":
[...], "support": [...], "checkIns": [...], "notes": [...], "totals": {...} }`,
with stable field names.

### 9.3 Prompt templates

The prompt is prepended to `summary.md`. Three variants exist:

- **Manager check-in — 1:1 (default):** highlights, per-project progress,
  collaboration, time allocation, risks, and three ready-to-paste bullets.
- **Manager check-in — performance review:** the same data, with evidence and
  measurable outcomes emphasised for a formal review.
- **Personal review:** where the time went, what moved, what did not, patterns
  worth changing, and up to three concrete changes for the next period.

All variants instruct the model to use only the supplied data, invent nothing,
cite links only when present, and output Markdown. The exact prompt text lives in
one versioned place in the service and is surfaced in Settings for preview.

### 9.4 Built-in AI generation

- One provider abstraction: OpenAI-compatible `POST {baseURL}/chat/completions`,
  streaming.
- The API key is read from the environment only. It is never stored in the
  database, exported, or logged.
- Only the selected period is sent. A settings toggle can strip URLs and notes.
- The response streams into the editable summary box, then persists with the model
  name and prompt version.
- Failures are explicit and non-destructive: the existing summary is untouched,
  with a retry action.

---

## 10. Backend shape and contracts

- Go module `github.com/Mallekoppie/wdid`, built on
  `github.com/Mallekoppie/goslow`.
- Connect is the only RPC transport. It serves Connect, native gRPC, and gRPC-Web
  from one handler. `internal/contracts/*.proto` is the single source of truth.
- The Flutter web client uses generated Dart stubs over gRPC-Web. It never
  hand-writes JSON DTOs or calls a REST endpoint for a capability that has an
  RPC.
- Hand-written implementations live in `internal/rpc/`, implement
  `platform.ConnectService`, and register the generated handlers.

**Proto files**

| File | Service | Purpose |
| --- | --- | --- |
| `auth.proto` | `AuthService` | Registration with invite, login, auth config, current user |
| `categories.proto` | `CategoryService` | Categories and subcategories |
| `entries.proto` | `EntryService` | Work entries, split, rollups |
| `milestones.proto` | `MilestoneService` | Project milestones |
| `timer.proto` | `TimerService` | Start, pause, resume, stop, active timer |
| `check_ins.proto` | `CheckInService` | Manager check-ins and personal reviews |
| `summaries.proto` | `SummaryService` | Export bundle, prompt, streaming summary |
| `settings.proto` | `SettingsService` | User settings, backups, restore |

**Representative RPCs**

- `CategoryService`: `ListCategories`, `CreateCategory`, `UpdateCategory`,
  `ArchiveCategory`, `ListSubcategories`, `CreateSubcategory`,
  `UpdateSubcategory`, `ArchiveSubcategory`.
- `EntryService`: `ListEntries`, `GetEntry`, `CreateEntry`, `UpdateEntry`,
  `DeleteEntry`, `SplitEntry`, `GetEntryRollup`.
- `MilestoneService`: `ListMilestones`, `CreateMilestone`, `UpdateMilestone`,
  `DeleteMilestone`.
- `TimerService`: `StartTimer`, `PauseTimer`, `ResumeTimer`, `StopTimer`,
  `GetActiveTimer`.
- `CheckInService`: `ListCheckIns`, `CreateCheckIn`, `GetCheckIn`,
  `UpdateCheckIn`, `FinalizeCheckIn`, `DeleteCheckIn`.
- `SummaryService`: `BuildExport`, `DownloadExport`, `BuildPrompt`,
  `GenerateSummary` (stream).
- `SettingsService`: `GetSettings`, `UpdateSettings`, `BackupNow`,
  `GetBackupStatus`, `ListBackups`, `RestoreBackup`.

**Rules**

- Public RPCs: registration, login, auth config. Every other RPC requires a
  bearer token. Admin RPCs are added to `Grpc.Server.ProcedureRoles` when the
  deferred admin surface lands.
- Identity is derived from the validated token, never from a request field.
- Instants use `google.protobuf.Timestamp` in UTC. Local calendar dates use
  `YYYY-MM-DD` strings. Durations use `google.protobuf.Duration`.
- List RPCs use `page_size` / `page_token` / `next_page_token`; the server caps
  page size.
- Request and response messages are distinct types.
- Errors use Connect codes with `google.rpc.BadRequest` field violations.
- No parallel REST/JSON surface for an RPC. Legacy handlers are retired as their
  RPC replacements land.

---

## 11. Backups and durability

- **Database:** `data/wdid.db` (BoltDB).
- **Backup directory:** configurable, default `backups/` next to the data
  directory.
- **Schedule:** on startup if the last backup is older than the interval
  (default 6 h), then at each interval while running; manual `Backup now`.
- **Mechanism:** `bolt.DB.View` + `tx.WriteTo(tmp)` to a temp file in the backup
  directory, `fsync`, then atomic rename to `wdid-YYYYMMDDTHHMMSSZ.db`. Never copy
  a live database file.
- **Verification:** open the new file read-only and read `sys:meta.schema_version`
  before reporting success.
- **Retention:** keep the newest N scheduled backups (default 30); never delete a
  manual backup automatically.
- **Restore:** stop writes, verify the chosen backup, move the current database to
  `wdid-before-restore-<timestamp>.db`, copy the backup into place, reopen, and
  rebuild indexes. Exposed in Settings and as `wdid backup|restore`.
- **Schema migrations** run on startup inside a transaction and always trigger a
  pre-migration backup.

Offsite replication (S3/R2/SFTP) and backup encryption are deferred. Backups stay
on the host filesystem, protected by directory permissions.

**Operational CLI (v1)**

- `wdid invite create --email …` — issue a single-use invite.
- `wdid invite list` / `wdid invite revoke <id>`.
- `wdid backup` / `wdid restore <file>`.

---

## 12. Key flows

1. **Start work** — Today → choose a category and subcategory (prefilled from the
   last timer) → describe what you are doing → Start. The timer pill appears
   everywhere.
2. **Switch work** — Timer pill → Stop & save (entry created) → choose the next
   category/subcategory → Start. "Save and switch" is one step.
3. **Capture after the fact** — Quick add or `N`, duration chip, category and
   optional subcategory, one-line summary; expand to add outcome and links.
4. **Log support** — `S` or `Log support` on Today → person, mode (subcategory),
   duration, what you did, outcome.
5. **Weekly personal review** — Review prompt or Check-ins → choose `Last 7 days`
   → scan allocation and outcomes → optionally generate a summary → record what
   to change → save the review, or leave without saving.
6. **Weekly tidy** — Log → `This week` → fix missing outcomes, split a long block,
   correct categories.
7. **Manager check-in** — Check-ins → create manager check-in → confirm the period
   since the last final manager check-in → generate or copy the prompt → edit →
   mark final → export.
8. **Invite a user** — admin runs `wdid invite create` → shares the code → the
   new user registers with it.
9. **Recovery** — Settings → Backups → choose a backup → Restore → confirm.

---

## 13. Milestones

| Milestone | Deliverable | Acceptance |
| --- | --- | --- |
| **M0 — Skeleton** | Dev container, Go module, goslow config, Makefile, Flutter web shell, proto generation | `make all`, `make test`, `make run` work in the container |
| **M1 — Identity and taxonomy** | Accounts, bootstrap admin, invite codes, per-user buckets, categories/subcategories, settings, migrations | Round-trip tests for every bucket; a second account cannot read the first account's data; invite codes are single-use |
| **M2 — Capture** | Timer service, global pill, Today screen, quick add, entry CRUD | Log a full day without touching the database directly |
| **M3 — Organise** | Log screen with filters and inline edit; Initiatives view; category management | A quarter of historical data can be entered and corrected |
| **M4 — Support** | Support log, quick add, rollups by person and mode | Support appears correctly in aggregates |
| **M5 — Check-ins and exports** | Manager check-ins, personal reviews, `summary.md` / `data.json` / CSVs, copy prompt | A pasted prompt produces a usable review draft; a personal review can be saved or discarded |
| **M6 — Built-in AI** | Provider config, streaming generation, prompt variants, persistence | Generated summary saves on the check-in; failures are non-destructive |
| **M7 — Durability** | Scheduled backups, restore, retention, status UI, CLI | Restore from a backup in a test instance; overdue warning works |
| **M8 — Polish** | Dark theme, keyboard shortcuts, empty/error states, accessibility pass | Keyboard-only check-in flow; AA contrast verified |

The order is deliberate: identity and taxonomy first, because every later entity
depends on both; durability last, because it protects a model that has stopped
moving.

---

## 14. Decisions, deferred scope, and open questions

### 14.1 Decisions taken (2026-10-23)

- The taxonomy is two levels: category → subcategory.
- Categories are per user, seeded with `Initiatives`, `Support`, and `Other`.
- Every category has an immutable reporting role: `initiative`, `support`, or
  `other`. Reporting and validation use the role, never the name.
- An entry has one required category and an optional subcategory from it.
- Subcategories carry optional project fields (status, progress, target outcome,
  target date, links) and milestones.
- Support is a role, not a separate entity. Person is required for support
  entries; support modes are subcategories; impact is the entry outcome.
- The canonical entity is a **work entry**.
- Check-ins have a kind: `manager` or `personal`. Only final manager check-ins
  move the period boundary.
- Personal reviews are on demand with a chosen timeframe; a weekly prompt is
  offered but no draft is auto-created. The cadence setting is
  weekly/monthly/off.
- Check-in audience (`1:1` or `performance review`) applies only to manager
  check-ins.
- Navigation keeps Today, Log, Initiatives, Support, Check-ins, Settings.
  Category management, backups, and exports live in Settings.
- Export bundle: `summary.md`, `data.json`, `entries.csv`, `support.csv`. No
  UI-builder export.
- Minutes are authoritative; no rounding. Overlapping manual entries are allowed
  and flagged.
- The AI key is environment-only.
- Backups are local and unencrypted in v1.
- Multi-user authentication and per-user isolation are in v1; admin UI, offsite
  push, WebAuthn, webhooks, and the review-readiness score are deferred.
- The project is **wdid**; no earlier working name is part of its vocabulary.

### 14.2 Deferred beyond v1

- Users & Access and OIDC management screens.
- Offsite backup push (S3/R2/SFTP) and backup encryption.
- Export webhooks.
- WebAuthn/passkeys.
- Review readiness score.
- Cross-attribution links (for example, a support entry pointing at a project).
- Arbitrary category nesting.
- Shared or team categories and instance-level category templates.
- Notification delivery (email, chat, push).
- Mobile capture, PWA install, calendar/issue-tracker imports.
- Charts beyond the weekly allocation bars.

### 14.3 Open questions

- Hosted operational details: TLS termination, monitoring, and who owns the
  deployment.
- Whether a personal-review streak or reminder should ever become a notification.
- The formula for a review-readiness score, if it is adopted later.
- Whether progress on an initiative subcategory should remain fully manual or
  later derive from milestones.
