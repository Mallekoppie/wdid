# wdid web client

Flutter web client for the wdid work journal.

## Status

This is the first UI slice, built against the canonical product model and design
documents in the repository root:

- `plan.md` (canonical product and domain model)
- `GLOSSARY.md`
- `.github/copilot-instructions.md`

Login, first-account bootstrap, and invite-code registration call the generated
`AuthService` gRPC-Web client in `lib/data/auth_api.dart`. The journal screens
still run against `DemoWdidRepository`, an in-memory stand-in exposed through the
`WdidRepository` seam in `lib/data/repository.dart`.

The demo adapter exists only so screens and flows can be reviewed. It does not
define the production contract, and it must be replaced by the gRPC-Web service
client. UI actions never bypass the seam: exports, summaries, aggregation, and
persistence all go through `WdidRepository`.

## Run

```bash
cd web
flutter pub get
flutter run -d chrome --dart-define=WDID_API_BASE_URL=http://127.0.0.1:8080
```

The auth client uses the page origin by default; set `WDID_API_BASE_URL` when the
service is on another origin, as with the Flutter dev server. `make serveweb`
passes it automatically.

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
| `/initiatives/:id` | Timeline, notes, milestones, evidence report |
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

`plan.md` supersedes the model this UI slice was built against. The current
service uses the earlier fixed `kind` shape (`initiative` / `support` / `other`);
the plan replaces it with per-user categories, subcategories, and reporting
roles. The service must migrate; `plan.md` is the target, not the current code.

The Go service transport is Connect, which serves Connect, native gRPC, and
gRPC-Web for the browser. `/healthz` is the only non-RPC route; there is no REST
surface.

- **Implemented by the service:** the auth RPCs. Login, invite-code registration,
  and first-account bootstrap call them via generated gRPC-Web stubs. The earlier
  Initiative and Work entry model still exists internally but is no longer
  exposed.
- **Not implemented by the service yet:** categories and subcategories,
  milestones, check-in records, personal reviews, notes, settings, and
  backup/restore. Those screens run on the demo adapter and surface the gap
  rather than inventing a persistence model.
- **Shape differences:** the earlier service shape used `kind`
  (`initiative`/`support`/`other`), `description`, and a nested `support` object.
  The plan replaces this with `categoryId` plus an optional `subcategoryId`. The
  protobuf contract is the source of truth; keep any temporary mapping in the
  repository adapter, not in screens.
- **Auth:** protected RPCs need `authorization: Bearer <token>` metadata from the
  local login RPC or a Zitadel token. The sign-in screen stores the session in
  memory; the browser OIDC redirect flow is still pending.

The UI demo currently uses the earlier `Initiative` / `WorkItem` shape. It must
migrate to the plan's model:

- `Category` (`name`, `role`, archived)
- `Subcategory` (`categoryId`, optional project fields, milestones)
- `Work entry` (`categoryId`, optional `subcategoryId`, `minutes`, `localDate`,
  `outcome`, `person` for support, links, tags)
- `Milestone`
- `CheckIn` (`kind`: `manager` or `personal`, `periodStart`, `periodEnd`, `state`,
  `summaryMarkdown`, `totals`)
- `Note`
- `AppSettings`

Known gaps, surfaced in the UI rather than invented locally:

- **Milestones** are defined in `plan.md` but have no service method yet. The
  project detail tab states this.
- **Categories and subcategories** are defined in `plan.md` but not implemented
  by the service yet.
- **Restore** is a host-level backup operation with no documented endpoint yet.
- **Auth** (Zitadel login and invite-code registration) has no service client in
  this slice; the login screen explains that.

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
