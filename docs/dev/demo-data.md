# Demo data

`wdid seed` fills a development database with a fixed demo account and a
deterministic dataset. It exists for local demos, UI smoke tests and manual
checks; nothing in the service calls it.

> **Development only.** The seeder refuses to run unless `WDID_DEV_MODE=true`.
> Never point it at production data: `--reset` replaces the whole target
> database. The demo loop binds to `127.0.0.1` and uses a separate database
> file from the normal dev database.

## Credentials

Every scenario seeds the same admin account:

| Field | Value |
| --- | --- |
| Email | `demo@wdid.local` |
| Password | `demo-password-123` |
| Display name | `Demo Admin` |
| Role | `admin` |

The seeder prints these values after every successful run. The password is
stored as a bcrypt hash, exactly like a normal local account.

## Quick start

```sh
make seed-demo   # seed/reset ./data/wdid-demo.db with the demo scenario
make run-demo    # serve it on http://127.0.0.1:9201
```

Then sign in at `http://127.0.0.1:9201` with the credentials above.

`make run-demo` seeds the database first if it does not exist. It runs in the
foreground; stop it with Ctrl-C.

### Raw equivalents

```sh
WDID_DEV_MODE=true WDID_DB_PATH=./data/wdid-demo.db \
  go run ./cmd/wdid seed --reset demo
WDID_DEV_MODE=true WDID_DB_PATH=./data/wdid-demo.db \
  WDID_HTTP_ADDR=127.0.0.1:9201 go run ./cmd/wdid
```

The command shape is
`wdid seed [--reset] [--anchor YYYY-MM-DD] [--fixture DIR] [--timezone TZ] <scenario>`.
Flags must come **before** the scenario name; Go's flag parser stops at the
first positional argument.

### Make variables

| Variable | Default | Meaning |
| --- | --- | --- |
| `DEMO_DB` | `./data/wdid-demo.db` | Target database file |
| `DEMO_ADDR` | `127.0.0.1:9201` | Listen address for `run-demo` |
| `DEMO_SCENARIO` | `demo` | Scenario passed to `seed` |
| `DEMO_ANCHOR` | empty (today, UTC) | `--anchor` date for reproducible timestamps |
| `SEED_ARGS` | `--reset` | Extra arguments such as `--reset` or `--anchor` |

Examples:

```sh
DEMO_SCENARIO=empty make seed-demo
DEMO_ANCHOR=2026-03-09 make seed-demo
SEED_ARGS= make seed-demo   # no --reset: refuses if the database exists
SEED_ARGS="--reset --timezone Asia/Tokyo" make seed-demo
SEED_ARGS="--reset --fixture ./my-fixture" make seed-demo
```

## Fixture overrides (`--fixture`)

The `demo` scenario reads an embedded declarative fixture split by domain:

| File | Contents |
| --- | --- |
| `taxonomy.json` | Categories, roles, projects/modes, status, progress and target outcome |
| `people.json` | Support-person roster |
| `settings.json` | Timezone, daily target and review cadence |
| `entries.json` | Work-entry templates expanded over the 14-day window ending at the anchor |
| `notes.json` | Day notes and project notes |
| `milestones.json` | Per-project milestones, due offsets and done state |
| `check_ins.json` | Manager check-in and personal review: periods, states, focus notes and summaries (totals are computed) |

`--fixture DIR` points at a directory that uses the same filenames. For each
domain file present in `DIR`, that file replaces the embedded domain. A file
that is missing from `DIR` falls back to the embedded copy, so a directory can
override one domain and inherit the rest. Other files in `DIR` are ignored.

The path must be an existing directory. A missing path, a path that is not a
directory, an unreadable file or invalid JSON (including an unknown field)
fails the seed with the offending file named. Because the seed is atomic, the
previous target database stays byte-identical.

```sh
WDID_DEV_MODE=true WDID_DB_PATH=./data/wdid-demo.db \
  go run ./cmd/wdid seed --reset --fixture ./my-fixture demo
```

Example `settings.json` override:

```json
{
  "timezone": "Europe/Amsterdam",
  "dailyTargetMinutes": 300,
  "reviewCadence": "monthly"
}
```

## `--timezone` semantics

`--timezone TZ` overrides the timezone in the fixture's `settings.json` (and,
for `empty`, the default `UTC`). It wins over the fixture and must be a name
that `time.LoadLocation` accepts, such as `Europe/Amsterdam` or `Asia/Tokyo`.
An invalid name fails the seed before the target database is touched. This is
useful for demoing a locale without editing the fixture.

## `--reset` semantics

* Without `--reset`, seeding refuses to overwrite an existing database and
  leaves it untouched. A missing database is created.
* With `--reset`, the existing database is replaced by the newly seeded one.
* `make seed-demo` passes `--reset` by default, so it always creates or resets
  the demo database. It never touches `./data/wdid.db`.

## Atomic replacement

The seeder never writes into the target database:

1. It creates a temporary database (`.wdid-seed-*.db`) in the target's
   directory.
2. It opens and seeds that temporary database, then closes it.
3. Only after the whole seed succeeds does it rename the temporary file over the
   target. The rename is atomic because both files are on the same filesystem,
   and the directory is synced afterwards.

If anything fails - an invalid scenario, a validation error, a bad anchor, a
storage failure - the temporary file is removed and the previous target stays
byte-identical. The target is never opened before the swap.

**Stop `make run-demo` before reseeding.** On Linux the rename succeeds while
the service holds the old file open, but the running process keeps serving the
old inode and silently ignores the new data. Stop the service, reseed, then
start it again.

## Scenarios

### `empty`

The account, default settings and the deterministic default taxonomy only:

* 1 user: `demo@wdid.local` (admin).
* 3 categories: `Initiatives` (no subcategories), `Support` (Review, Pair,
  Unblock, Mentor, Incident, Other), `Other` (Meetings, Admin, Learning,
  Unplanned).
* Default settings: `UTC`, week starts Monday, 450-minute daily target,
  personal review off, 240-minute long-timer prompt, 30-minute default
  duration, 6-hour backup interval, 30-snapshot retention.
* The settings record also carries the internal `SupportPeopleSeeded` marker
  (`true`), so loading settings never populates the roster. The `empty`
  scenario has no entries to derive support names from, and its roster stays
  deliberately empty even though the default taxonomy includes support modes.
* 0 work entries, 0 notes, 0 milestones, 0 check-ins, no active timer.

Identifiers are derived from the scenario name and stable labels with
`uuid.NewSHA1`, never random, so reseeding the same scenario reproduces the same
IDs. All timestamps derive from the anchor date; two runs with the same anchor
produce identical content (the bcrypt salt and the database instance ID are the
only intentionally non-identical values).

### `demo`

The account plus the embedded fixture: **5 categories, 16 subcategories, 62
work entries, 11 notes, 20 milestones, 2 check-ins, 1 user**, and the demo
settings below. There is no active timer.

#### Taxonomy and projects

Initiative-role subcategories are projects; support-role subcategories are
support modes; other-role subcategories are overhead categories.

| Category | Role | Project/mode (status, progress) |
| --- | --- | --- |
| Client Delivery | initiative | Acme migration (active, 60%), Globex onboarding (active, 35%), Initech audit (done, 100%) |
| Platform | initiative | Auth overhaul (active, 45%), Search relevance (blocked, 25%), Observability (planned, 0%) |
| Growth | initiative | Self-serve trial (active, 70%), Pricing experiment (planned, 10%) |
| Support | support | Mentoring, Pairing, Incident support, Code review, 1:1 (all active) |
| Other | other | Meetings, Admin, Learning (all active) |

Category and subcategory sort order is the order shown above. The initiative
projects carry these target outcomes:

| Project | Target outcome |
| --- | --- |
| Acme migration | Acme's production workloads run entirely on the new platform. |
| Globex onboarding | Globex is live and its team can operate without hand-holding. |
| Initech audit | Audit findings are delivered and signed off. |
| Auth overhaul | One auth path serves every client with session rotation. |
| Search relevance | The benchmark query set returns its expected result in the top three. |
| Observability | Every request is traceable end to end with actionable alerts. |
| Self-serve trial | A new account reaches first value without human help. |
| Pricing experiment | One pricing model is chosen from the experiment results. |

#### Roster and settings

Support-person roster, in order: **Priya, Sam, Alex, Jordan, Mei, Diego, Noor,
Chris**.

| Setting | Value |
| --- | --- |
| Timezone | `UTC` (override with `--timezone` or `settings.json`) |
| Week starts | Monday (default) |
| Daily target | 450 minutes (`7.5`) |
| Personal review cadence | `weekly` |
| Support people | The eight-person roster above |
| `SupportPeopleSeeded` | `true`, so loading settings never rewrites the roster |

Everything else (long-timer prompt, default duration, backup interval,
retention, theme, density) keeps the account defaults documented for `empty`.

#### Notes

The fixture seeds **11 notes**: eight day notes and three project notes. A day
note has a date and no project; a project note has an initiative project and no
date. Every date is an offset from `--anchor`, so the dataset stays inside the
14-day demo window for any anchor. The anchor-day note (`daysBeforeAnchor: 0`)
is the note Today displays. Example dates below use `--anchor 2026-03-09`.

| Days before anchor | Example date | Day note |
| --- | --- | --- |
| 13 | 2026-02-24 | Planning the next two weeks. Cut scope on the audit deliverable and protected Friday for review. |
| 11 | 2026-02-26 | Incident support in the afternoon. No customer impact, but the alert threshold needs tuning. |
| 9 | 2026-02-28 | Deep work on the pricing experiment. Three variants defined; waiting on finance for the margin floor. |
| 6 | 2026-03-03 | Client check-in with Globex. They want the onboarding runbook before the next cohort. |
| 5 | 2026-03-04 | Blocked most of the morning on staging credentials, then finished the observability dashboard skeleton. |
| 3 | 2026-03-06 | Pairing with Priya on the auth session rotation. The refresh-token edge case is real; wrote it up as a milestone. |
| 1 | 2026-03-08 | Review day. Triaged the search relevance benchmark failures and parked the pricing copy until next week. |
| 0 | 2026-03-09 | Cutover dry run complete. Tomorrow: tighten the rollback window and confirm the Globex contact list. |

The three project notes attach to different initiative projects, so each project
detail screen shows one:

| Project (category) | Days before anchor | Example date | Note |
| --- | --- | --- | --- |
| Acme migration (Client Delivery) | 2 | 2026-03-07 | The dry run surfaced two ordering gaps in the migration scripts. Both are fixed; the remaining risk is the rollback window, which needs a signed runbook before the cutover. |
| Search relevance (Platform) | 7 | 2026-03-02 | The **long note**: 2,366 characters in one unwrapped paragraph, from "The benchmark review turned into a longer investigation than expected" to "reconstruct it afterward." The full text lives in `notes.json`; the UI renders it without a `maxLines` clamp, so the project-detail page must not overflow horizontally. |
| Self-serve trial (Growth) | 10 | 2026-02-27 | The trial cohort reached first value faster than the last one, mostly because the empty state now points at a sample project. Next question is whether the pricing page should appear before or after the first saved entry. |

All note texts stay under the 4,000-character domain limit.

#### Milestones

Each initiative project carries **2-3 milestones** (20 in total, 2-3 per
project). There is no status field: status is derived from `done` and the due
date relative to the anchor.

* **done**: `done` is true and the due date is before the anchor.
* **overdue**: not done and the due date is before the anchor.
* **upcoming**: not done and the due date is on or after the anchor. A due date
  equal to the anchor (`dueOffsetDays: 0`) counts as upcoming.

The fixture produces **9 done, 4 overdue and 7 upcoming** milestones. Example
dates below use `--anchor 2026-03-09`; `dueOffsetDays` is relative to the anchor.

| Project | Title | Due offset | Example due | Done | Status |
| --- | --- | --- | --- | --- | --- |
| Acme migration | Cutover dry run completed | -10 | 2026-02-27 | yes | done |
| Acme migration | Rollback window signed off | -2 | 2026-03-07 | no | overdue |
| Acme migration | Production cutover | 7 | 2026-03-16 | no | upcoming |
| Globex onboarding | Kickoff workshop delivered | -12 | 2026-02-25 | yes | done |
| Globex onboarding | Admin training runbook | 0 | 2026-03-09 | no | upcoming |
| Initech audit | Evidence pack delivered | -20 | 2026-02-17 | yes | done |
| Initech audit | Findings signed off | -6 | 2026-03-03 | yes | done |
| Auth overhaul | Session rotation design approved | -9 | 2026-02-28 | yes | done |
| Auth overhaul | Refresh-token edge case fixed | -1 | 2026-03-08 | no | overdue |
| Auth overhaul | Client migration | 10 | 2026-03-19 | no | upcoming |
| Search relevance | Benchmark set frozen | -15 | 2026-02-22 | yes | done |
| Search relevance | Top-three result reached | -4 | 2026-03-05 | no | overdue |
| Observability | Trace pipeline selected | 6 | 2026-03-15 | no | upcoming |
| Observability | First dashboard live | 14 | 2026-03-23 | no | upcoming |
| Self-serve trial | Signup flow instrumented | -8 | 2026-03-01 | yes | done |
| Self-serve trial | First-value milestone defined | -3 | 2026-03-06 | yes | done |
| Self-serve trial | Cohort launch | 5 | 2026-03-14 | no | upcoming |
| Pricing experiment | Experiment brief written | -7 | 2026-03-02 | yes | done |
| Pricing experiment | Finance margin floor confirmed | -1 | 2026-03-08 | no | overdue |
| Pricing experiment | Experiment readout | 12 | 2026-03-21 | no | upcoming |

Work entries (ticket #8) and check-ins (ticket #10) are separate fixture
domains listed above.

Fixture-owned rows use deterministic IDs derived from the scenario and stable
labels, and every timestamp derives from `--anchor`; rerunning the same
scenario with the same anchor and fixture produces identical IDs and content.
The bcrypt salt and the database instance ID are the only intentionally
non-identical values.

#### Work entries

`entries.json` holds 14 templates. Each template names a window-relative day
selector, a local wall-clock start, duration, category/project or mode, optional
person, description, optional outcome and source. A selector is expanded once
per matching day, so the dataset shape does not depend on the anchor's weekday:

| Selector | Matching days | Entries per matching day |
| --- | --- | --- |
| `normal-weekday` | every weekday in the window except the sparse day | 6 |
| `sparse` | the first weekday in the window | 2 |
| `on-call` | the latest Saturday on or before the anchor | 5 |
| `anchor` | the anchor day | 1 (the no-mode interrupt) |

The window is the 14 calendar days `anchor-13 .. anchor` inclusive in the
resolved settings timezone (`UTC` by default). Every 14-day window contains two
Saturdays; the on-call day is the later one (the latest Saturday on or before
the anchor). The sparse day is the first weekday in the window, and the other
weekend days are empty apart from the anchor-day interrupt when the anchor
itself falls on a Sunday.

The resulting shape for any anchor:

* 62 entries across the 14 days.
* Normal weekdays: 6 entries; a weekday anchor also carries the interrupt (7).
* Sparse day: 2 entries.
* On-call Saturday: 5 support entries; a Saturday anchor also carries the
  interrupt (6).
* Weekend anchor that is not the on-call Saturday (a Sunday): only the
  interrupt.
* Other weekend days: 0 entries.
* Every day's blocks are non-overlapping local times between 08:45 and 16:45.

Attribution uses the seeded taxonomy and roster. Weekday templates cover
Client Delivery, Platform and Growth projects plus `Other · Meetings`; the
sparse day uses `Other · Learning` and `Client Delivery · Acme migration`; the
on-call day covers all five support modes (`Incident support`, `Pairing`,
`Mentoring`, `Code review`, `1:1`) with roster people. Entries mix `timer` and
`manual` sources.

Exactly one support entry has **no mode** and falls on the **anchor day**, so
Today renders it as `No mode` with a `Set mode` action. It is the 15-minute
`Support · Priya` row starting at 15:30.

Representative literal rows (stable for any anchor; only the date moves):

| Day | Time | Attribution | Description | Minutes | Source |
| --- | --- | --- | --- | --- | --- |
| Any normal weekday | 08:45 | Client Delivery · Acme migration | Migration standup and blocker triage | 30 | timer |
| Any normal weekday | 09:15 | Platform · Auth overhaul | Session rotation implementation | 90 | manual |
| Anchor day | 15:30 | Support · Priya · No mode | Unblocked Priya on the migration cutover | 15 | manual |

UI smoke tests can assert the anchor-day no-mode row
`Unblocked Priya on the migration cutover`, the `No mode` / `Set mode` labels,
and an initiative row such as `Migration standup and blocker triage` under
`Client Delivery · Acme migration`.

#### Check-ins

`check_ins.json` seeds **2 artifacts** after the work entries. Totals are never
declared in the fixture: each check-in snapshots the authoritative period report
for its own inclusive period. That snapshot must happen before the first save
because a final manager check-in is read-only immediately afterwards. Period and
creation offsets are days before the anchor, so the dataset moves with
`--anchor`.

| Artifact | Kind | State | Audience | Period | Example period (`--anchor 2026-03-09`) | Created at |
| --- | --- | --- | --- | --- | --- | --- |
| Manager check-in | `manager` | `final` | `one_on_one` | `anchor-13 .. anchor-7` | 2026-02-24 .. 2026-03-02 | `anchor-7` 18:00 UTC |
| Personal review | `personal` | `draft` | none | `anchor-6 .. anchor` | 2026-03-03 .. 2026-03-09 | `anchor` 18:00 UTC |

The check-in list is newest first, so the personal review appears first. The
final manager check-in is the boundary returned by `LastFinalManagerCheckIn`;
the personal review remains editable through `SaveCheckIn` and never moves that
boundary. Any edit to the final manager (or an attempt to delete it) returns
`ErrFinalCheckInReadOnly`.

Manager focus notes:

> Cutover readiness, Globex onboarding and the auth refresh-token fix. Keep
> support time visible next period.

Manager summary (`summaryMarkdown`):

```markdown
## Previous period

Shipped the auth session-rotation foundation and closed two migration ordering gaps. The Acme cutover is the main risk: the rollback window still needs a signed runbook.

- Acme migration: dry run complete, blockers assigned
- Globex onboarding: import rehearsal clean
- Support: on-call coverage only, no escalations
```

Personal review focus notes:

> What moved the projects forward this week, and where did support work
> interrupt deep work?

Personal review summary (`summaryMarkdown`, draft):

```markdown
## Draft review

Steady progress on the self-serve trial and search relevance. Support stayed bounded to the on-call day. Next: protect a longer block for the cutover runbook.
```

For `--anchor 2026-03-09` the report snapshots are:

| Artifact | Minutes | By category (ID keys, documented by name) | Support by person |
| --- | --- | --- | --- |
| Manager check-in | 1545 | Client Delivery 420, Platform 540, Growth 300, Other 285 | none |
| Personal review | 2070 | Client Delivery 450, Platform 675, Growth 375, Other 300, Support 270 | Alex 90, Sam 45, Noor 60, Mei 30, Jordan 30, Priya 15 |

By subcategory (ID keys, documented by name):

* **Manager**: Acme migration 180, Auth overhaul 360, Globex onboarding 240,
  Meetings 240, Self-serve trial 300, Search relevance 180, Learning 45.
* **Personal**: Acme migration 150, Auth overhaul 450, Globex onboarding 300,
  Meetings 300, Self-serve trial 375, Search relevance 225, Incident support 90,
  Pairing 45, Mentoring 60, Code review 30, 1:1 30. The 15-minute no-mode
  support row counts in the total and support-by-person but has no subcategory
  key.

Re-running the same scenario, anchor and fixture reproduces the same check-in
IDs and content.

### Expected `empty` screens

The full per-screen manual checklist is ticket #11; this is the short version
of the empty states.

| Screen | Expected |
| --- | --- |
| Today | `Nothing logged yet` / `Capture your first entry above.`; `Start a timer` present and idle; `0m this week`; `No time logged in this period.`; empty day note |
| Log | `Nothing logged in this period` / `Capture work on Today or widen the date range.`; `Add entry` |
| Initiatives | `0 projects · 0m logged this quarter`; `No projects yet`; `New project` |
| Project detail | Not reachable; a direct URL reports the project is not found |
| Support | `No people yet. Add a name here or while logging support.`; `No support logged in this period`; `Log support` |
| Check-ins | `No check-ins yet`; `Create check-in`; the live review shows `Nothing logged in this period` and `Save empty review` |
| Settings | `UTC`, daily target `7.5`, personal review `Off`, and the default taxonomy above |

## Manual UI checklist

`make smoke-seeded` is the automated companion to this checklist. It seeds a
throwaway database per scenario, starts the service on `127.0.0.1:9202`, and
walks all six screens with Playwright; `./data/` is never touched. It needs
Node and Playwright: `node -e "require('playwright')"` must resolve, either via
`npm install --no-save playwright` or by pointing `NODE_PATH` at an existing
install (`NODE_PATH=/path/to/node_modules make smoke-seeded`).

**Use the current UTC date as the anchor.** The service resolves Today and
"This week" from its own clock (`EntryService.ListEntries` with `today` and
`SummaryService.GetPeriodReport` with `currentWeek`), not from the browser. A
seeded anchor in the past therefore leaves Today empty even though every other
screen shows the data. `make smoke-seeded` derives the anchor from
`date -u +%F`, seeds with `--anchor <date>`, and freezes the browser clock to
the same date at midday UTC. Do the same by hand:

```sh
make seed-demo          # --anchor defaults to today, UTC
make run-demo           # http://127.0.0.1:9201

# Empty scenario, afterwards:
DEMO_SCENARIO=empty make seed-demo
make run-demo
```

Sign in as `demo@wdid.local` / `demo-password-123`. All dates below use an
**example Monday anchor (2026-03-16)** for a concrete layout. Content that does
not depend on the anchor - descriptions, note text, project and milestone
titles, check-in totals and settings - is identical on every run. Date-derived
content moves with the anchor:

* The 14-day window is `anchor-13 .. anchor`.
* The sparse day is the first weekday in the window.
* The on-call day is the latest Saturday on or before the anchor.
* Today shows the six normal-weekday rows plus the 15-minute interrupt on any
  weekday, the five on-call rows plus the interrupt on Saturday, and only the
  interrupt on Sunday.
* The full window always has 62 entries / 60h 15m. The Log's "days shown"
  counts only days with entries: 11 for a Monday-Saturday anchor, 12 for a
  Sunday anchor (the anchor-day interrupt).
* The manager and personal check-in halves are anchor-invariant: 26 entries /
  25h 45m and 36 entries / 34h 30m.

### `demo` scenario

| Screen | Expected |
| --- | --- |
| Today | Heading date equals the anchor (e.g. `Mon 16 Mar 2026`); idle `Start a timer`, no `Running`/`Timer paused` card. Anchor-day rows include `Client Delivery · Acme migration` / `Migration standup and blocker triage`, `Platform · Auth overhaul` / `Session rotation implementation`, `Client Delivery · Globex onboarding` / `Globex data import rehearsal`, `Other · Meetings` / `Delivery sync and planning`, `Growth · Self-serve trial` / `First-run onboarding experiment`, `Platform · Search relevance` / `Benchmark query tuning`, and `Support · Priya` / `Unblocked Priya on the migration cutover` with `No mode` + `Set mode` (on a weekday; see the weekday rule above). `Week by category` is populated. Example Monday anchor: `6h 15m this week`, `6h 15m logged this week`; a Sunday anchor shows `34h 30m`. The note textarea holds `Cutover dry run complete. Tomorrow: tighten the rollback window and confirm the Globex contact list.` |
| Log | Choose period `This month`: the full 14-day window is in range for a mid/late-month anchor. The full window is `60h 15m`; the header reports the days with entries (`11 days shown`, or `12` for a Sunday anchor). Category menu lists `Client Delivery`, `Platform`, `Growth` (plus `Support`, `Other`); after choosing `Client Delivery`, the Subcategory menu lists `Acme migration`, `Globex onboarding`, `Initech audit`. With both filters set: `5h 30m · 10 days shown` for the full window, and rows include `Migration standup and blocker triage` and `Short migration pairing session`. |
| Initiatives | `8 projects · 46h logged this quarter` when the full window is inside the current quarter (true for a mid-quarter anchor). Cards for Acme migration, Globex onboarding, Initech audit, Auth overhaul, Search relevance, Observability, Self-serve trial and Pricing experiment, with categories, statuses (`Active`, `Blocked`, `Planned`, `Done`), target outcome and progress (Acme 60%, Globex 35%, Initech 100%, Auth 45%, Search 25%, Observability 0%, Self-serve 70%, Pricing 10%). |
| Project detail | Open **Acme migration**: `Client Delivery`, target outcome `Acme's production workloads run entirely on the new platform.`, `60%`. Notes tab: `The dry run surfaced two ordering gaps in the migration scripts. Both are fixed; the remaining risk is the rollback window, which needs a signed runbook before the cutover.` Milestones tab: `3 milestones`, `Cutover dry run completed` checked with `Due <anchor-10>`, `Rollback window signed off` unchecked with `Due <anchor-2>`, `Production cutover` unchecked with `Due <anchor+7>` (Monday anchor example: `6 Mar`, `14 Mar`, `23 Mar`). Report tab: `Project report`, `This quarter 5h 30m`, `Entries 10`, `1 of 3 complete`. Also open **Search relevance** → Notes: the long benchmark note (starts `The benchmark review turned into a longer investigation…`, ends `…reconstruct it afterward.`) renders with no horizontal page overflow. |
| Support | `4h 30m · 6 people · 6 interactions`. People chips for Priya, Sam, Alex, Jordan, Mei, Diego, Noor, Chris. `By mode` shows Incident support 1h 30m, Mentoring 1h, Pairing 45m, Code review 30m, 1:1 30m; `By person` lists the six supported people (Alex 1h 30m, Noor 1h, Sam 45m, Jordan 30m, Mei 30m, Priya 15m). The feed includes `Support · Alex · Incident support`, the rest of the on-call rows, and the mode-less `Support · Priya · No mode` row. |
| Check-ins | Subtitle `2 shown`, newest first. Manager card period `<anchor-13> → <anchor-7>` (Monday example `3 Mar → 9 Mar 2026`) with `Manager`, `1:1`, `Final`, `25h 45m`, `7` days; personal card period `<anchor-6> → <anchor>` (`10 Mar → 16 Mar 2026`) with `Personal`, `Draft`, `34h 30m`, `7` days. Manager detail: `Final check-in — read-only boundary for the next period.`, stats 25h 45m / 7 days / 26 entries / 0m support / 0 interactions, aggregates `Time by category` (Client Delivery 7h, Platform 9h, Growth 5h, Other 4h 45m), `Time by project`, `Support by person`, `Weekly rhythm`. Personal detail: `Personal review — editable, and never moves the manager boundary.`, 34h 30m / 7 days / 36 entries / 4h 30m support / 6 interactions, the focus notes and the `## Draft review` summary (`Steady progress on the self-serve trial and search relevance.`); `Edit review` opens a period dialog with `Cancel` and `Save review` (cancel it, do not save). Live review `#/checkins/review?start=<anchor-13>&end=<anchor>`: `14 days`, logged `60h 15m`, entries `62`, support `4h 30m`, with the same aggregate panels. Do not save. |
| Settings | `Timezone` `UTC`, week starts Monday, `Daily target` `7.5`, `Personal review` `Weekly`. Categories list Client Delivery, Platform, Growth, Support, Other with the project and mode chips (Acme migration … 1:1; Meetings, Admin, Learning). |

### `empty` scenario

| Screen | Expected |
| --- | --- |
| Today | `Nothing logged yet` / `Capture your first entry above.`; idle `Start a timer`; `0m this week`; `Week by category` shows `No time logged in this period.`; the day-note textarea is empty. |
| Log | Default `This week`: `Nothing logged in this period` / `Capture work on Today or widen the date range.` and the `Add entry` action. |
| Initiatives | `0 projects · 0m logged this quarter`, `No projects yet`, `New project`. |
| Project detail | No card to open; a direct `#/initiatives/<id>` URL reports the project is not found. |
| Support | Header `0m · 0 people · 0 interactions`; `No people yet. Add a name here or while logging support.`; `No support logged in this period`; `Log support`. |
| Check-ins | Subtitle `Turn captured work into a review-ready period report.`; `No check-ins yet`; `Create check-in`. Live review `#/checkins/review` shows `Nothing logged in this period` and `Save empty review`. |
| Settings | `Timezone` `UTC`, `Daily target` `7.5`, `Personal review` `Off`. Categories: `Initiatives` (`No subcategories.`), `Support` (Review, Pair, Unblock, Mentor, Incident, Other), `Other` (Meetings, Admin, Learning, Unplanned). |

## Where the data lives

* Database: `./data/wdid-demo.db` (gitignored, like all `*.db` files).
* Normal development data stays in `./data/wdid.db`; the demo loop never
  touches it.
* Backups default to `./data/backups` and may mix with normal dev backups. Set
  `WDID_BACKUP_DIR` if you want the demo instance isolated.
