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

`--fixture DIR` points at a directory that uses the same filenames. For each
domain file present in `DIR`, that file replaces the embedded domain. A file
that is missing from `DIR` falls back to the embedded copy, so a directory can
override one domain and inherit the rest. Other files in `DIR` are ignored;
later tickets add `notes.json`, `milestones.json` and `check_ins.json` without
changing the command.

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
* 0 work entries, 0 notes, 0 milestones, 0 check-ins, no active timer.

Identifiers are derived from the scenario name and stable labels with
`uuid.NewSHA1`, never random, so reseeding the same scenario reproduces the same
IDs. All timestamps derive from the anchor date; two runs with the same anchor
produce identical content (the bcrypt salt and the database instance ID are the
only intentionally non-identical values).

### `demo`

The account plus the embedded fixture: **5 categories, 16 subcategories, 62
work entries, 1 user**, and the demo settings below. Notes, milestones and
check-ins are still **0**; tickets #9 and #10 add those domains as independent
fixture files. There is no active timer.

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

## Where the data lives

* Database: `./data/wdid-demo.db` (gitignored, like all `*.db` files).
* Normal development data stays in `./data/wdid.db`; the demo loop never
  touches it.
* Backups default to `./data/backups` and may mix with normal dev backups. Set
  `WDID_BACKUP_DIR` if you want the demo instance isolated.
