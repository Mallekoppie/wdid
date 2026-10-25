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

The command shape is `wdid seed [--reset] [--anchor YYYY-MM-DD] <scenario>`.
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
```

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

> Placeholder until ticket #7. `demo` is registered and documented now, but
> currently seeds the same account, settings and taxonomy as `empty`, with no
> work rows. Tickets #7-#10 add the declarative fixture (projects, entries,
> notes, milestones and check-ins) without changing the command.

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
