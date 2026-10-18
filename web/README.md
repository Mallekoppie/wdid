# wdid web client

Flutter web client for the wdid / LogLoop work journal.

## Status

This is the first UI slice, built against the product and design documents in the
repository root:

- `plan.md`
- `stich-design.md`
- `.github/copilot-instructions.md`

The Go service is not connected yet. The UI runs against
`DemoWdidRepository`, an in-memory stand-in exposed through the
`WdidRepository` seam in `lib/data/repository.dart`.

The demo adapter exists only so screens and flows can be reviewed. It does not
define the production contract, and it must be replaced by the gRPC-Web service
client. UI actions never bypass the seam: exports, summaries, aggregation, and
persistence all go through `WdidRepository`.

## Run

```bash
cd web
flutter pub get
flutter run -d chrome
```

Validation:

```bash
cd web
flutter analyze
flutter test
flutter build web
```

## Routes

| Route | Screen |
| --- | --- |
| `/today` | Timer, quick capture, today's feed, week allocation, day note |
| `/log` | Period filters, search, grouped entries, inline edit, export |
| `/initiatives` | Portfolio cards and archived initiatives |
| `/initiatives/:id` | Timeline, notes, milestones (contract pending), evidence report |
| `/support` | Support rollups by mode and person, support feed |
| `/checkins` | Check-in list and create flow |
| `/checkins/:id` | Period report, summary generation/editing, export, finalize |
| `/settings` | Data/backups, time, AI, appearance, about |
| `/login` | Zitadel/invite sign-in shell (auth service pending) |

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| `T` | Start or stop the timer |
| `N` | New entry |
| `S` | Log support |
| `/` | Go to Log and focus search |
| `G` then `T/L/I/C/S` | Navigate to Today, Log, Initiatives, Check-ins, Support |
| `?` | Shortcut reference |

## Design notes

- Deep Teal (`#00696D`) Material 3 seed, light/dark/system/high-contrast themes.
- Comfortable and compact densities.
- Tabular figures for all times, durations, and percentages.
- Support entries use the tertiary tint and `volunteer_activism` icon.
- Cards are 12 px, inputs 8 px, and the layout stays desktop/tablet-first.
- Loading, empty, error, and validation states are explicit on every screen.

## Service contract status

The Go service landed after this UI slice started. Its transport is moving to
gRPC with gRPC-Web for the browser; the legacy REST surface is narrower than the
product sample documents and is retired as RPCs land.

- **Implemented by the service:** initiatives, work entries, timer, period
  summary, exports, and auth.
- **Not implemented by the service yet:** check-in records, notes, settings, and
  backup/restore. Those screens run on the demo adapter and surface the gap
  rather than inventing a persistence model.
- **Shape differences:** the current HTTP mapping uses `kind`
  (`initiative`/`support`/`other`), `description`, and a nested `support` object.
  The protobuf contract is the source of truth; keep any temporary mapping in the
  repository adapter, not in screens.
- **Auth:** protected RPCs need `authorization: Bearer <token>` metadata from the
  local login RPC or a Zitadel token. The sign-in screen is a shell until
  token/session handling is wired.

The UI demo currently expects the entities and fields documented in `plan.md`:

- `Initiative`
- `WorkItem` (`type`, `initiativeId`, `category`, `categoryLabel`, `minutes`,
  `localDate`, `outcome`, `person`, `team`, links, tags)
- `CheckIn` (`periodStart`, `periodEnd`, `state`, `summaryMarkdown`, `totals`)
- `Note`
- `AppSettings`

Known documentation gaps, surfaced in the UI rather than invented locally:

- **Milestones** are described in the design but have no entity or service
  method in the documented contract. The initiative detail tab states this.
- **Restore** is a host-level backup operation with no documented endpoint yet.
- **Auth** (Zitadel login, invite registration, break-glass passkey) has no
  service client in this slice; the login screen explains that.

Next steps for integration:

1. Run `make proto` and add `ServiceWdidRepository` over the generated Dart
   clients with a `GrpcWebClientChannel.xhr` channel, bearer-token metadata, and
   explicit deadlines.
2. Add the remaining RPCs for check-ins, notes, settings, and backup/restore, or
   keep those features demo-only until the contract exists.
3. Map `GrpcError` codes and `errdetails.BadRequest` field violations onto the
   existing loading, empty, error, and validation states.
4. Switch `main.dart` to the service repository. No screen changes should be
   required.
