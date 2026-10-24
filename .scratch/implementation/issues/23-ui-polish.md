# 23: UI polish

**What to build:** Every screen feels like one product: the four themes, comfortable and compact densities, keyboard shortcuts, visible focus, loading and empty and error states, and accessible contrast. The five-second capture path stays fast.

**Blocked by:** 04–20 and 22 (all feature slices)

**Status:** ready-for-human

- [x] System, Light, Dark, and High Contrast themes work with the Deep Teal seed.
- [x] Comfortable and Compact densities apply consistently.
- [x] Keyboard shortcuts work: `T`, `N`, `S`, `G` then `T`/`L`/`I`/`C`, `/`, and `?`.
- [x] Every screen has explicit loading, empty, error, validation, and success states.
- [x] Focus rings are visible and full keyboard operation is possible.
- [x] Colour pairs meet WCAG AA; timer state is conveyed by more than colour.
- [x] Times and durations use tabular figures and ISO-like date order.
- [x] No regression in the quick-capture flow.

## Comments

### What changed

- `web/lib/theme/app_theme.dart` — retained the single Deep Teal seed (`#00696D`)
  for System/Light/Dark/High Contrast. Added an explicit focus treatment:
  `focusColor`, a focused `side` on filled/outlined/text/icon buttons (2 px
  primary ring) and `AppTheme.isCompact(context)` for density-aware widgets.
- `web/lib/widgets/focus_ring.dart` (new) — a reusable 2 px ring painted over a
  control whenever its subtree owns keyboard focus. `nav_rail.dart` wraps every
  destination in it; nav row height also follows density.
- `web/lib/widgets/work_entry_row.dart` and `support_entry_row.dart` — vertical
  padding now follows the active density (`10/9` comfortable, `6/5` compact)
  in addition to the existing `EntryRow` 48/36 px rows.
- `web/lib/widgets/app_shell.dart` — `?` now also matches
  `LogicalKeyboardKey.question`, so Shift+/ works on layouts where the key
  arrives as a question key. All other shortcuts were already wired.
- `web/lib/screens/settings_screen.dart` — theme and density changes now emit
  explicit success snackbars ("Theme set to X" / "Density set to X"); failures
  were already surfaced.
- `web/lib/screens/initiative_detail_screen.dart` — deep links to a project
  that is still loading now show `LoadingView` (and `ErrorView` with retry on
  failure) instead of briefly rendering "Initiative not found".
- `web/lib/widgets/forms/entry_dialog.dart` — the dialog footer text is now
  flexible and ellipsised, removing a real horizontal overflow under wide text
  metrics (the N shortcut exercised it).

### Per-checkbox evidence

1. **Themes with Deep Teal seed** — `AppTheme.seed` is asserted in
   `web/test/ui_polish_test.dart` ("all four theme preferences build from the
   Deep Teal seed"), including System light/dark resolution and that High
   Contrast strengthens the generated scheme. `web/lib/app.dart` maps all four
   preferences (plus `ThemeMode.system`) onto `MaterialApp.router`.
2. **Comfortable/Compact density** — `AppTheme.build` sets `visualDensity` and
   `ListTileThemeData.dense`; the settings UI updates it live. Tests: "comfortable
   and compact densities change the shared theme", "settings applies theme and
   density immediately", and "compact density tightens data rows" (row padding
   10 → 6). Existing persistence is covered by `app_state_taxonomy_test.dart`.
3. **Keyboard shortcuts** — `web/lib/widgets/app_shell.dart` handles `T`, `N`,
   `S`, the `G` chord (`T/L/I/C`, plus the already-supported `S`), `/`, and `?`
   while ignoring typing. Tests in `ui_polish_test.dart` press each key and
   assert the resulting state/route/dialog; the `/` test asserts the Log search
   `FocusNode.hasFocus`.
4. **Per-screen states** — see the screen-by-screen table below. Missing
   initiative-detail loading/error states were added; all other screens already
   had explicit states, now recorded as evidence.
5. **Focus rings / keyboard operation** — `FocusRing` plus themed focused
   borders. Tests: "theme focus treatment is strong enough to see" (focusColor
   alpha and 2 px focused side on every theme), "focus ring appears on keyboard
   focus and Enter activates" (autofocus → ring key present → Enter fires the
   callback), and "navigation rail exposes a focus ring for every destination".
   Tab traversal, Enter activation, `/` search focus and the G-chord route
   changes exercise end-to-end keyboard operation.
6. **WCAG AA and non-colour timer state** — "generated schemes meet AA for text
   and UI pairs" computes ratios from the actual theme tokens for all four
   preferences. Worst text pair is ≥4.5 (light outline/UI pair 4.27 ≥ 3; dark
   outline 5.89; High Contrast ≥ 8.98 for all text pairs). `timer_pill.dart`
   already pairs colour with the `timer_outlined`/`pause_circle_outline` icons
   and the literal "Paused" label, asserted by "running and paused states use
   icon and text cues".
7. **Tabular figures / ISO-like dates** — `app_tokens.dart` exposes
   `tabularFigures`; `time_utils.dart` formats `yyyy-MM-dd`, `HH:mm`, `d MMM`
   and `EEE d MMM yyyy`. Tests assert ISO order (`2025-10-17`, `09:05`, `17 Oct
   2025`), and that `EntryRow` time/duration text (and `displaySmall`) carry the
   `tnum` font feature.
8. **Quick capture** — the existing `web/test/today_quick_capture_test.dart`
   still covers the five-second path (default duration, remembered pair, support
   person validation, success/undo, loading/error/empty). Added a dedicated
   regression in `ui_polish_test.dart`: Enter on the one-line field creates the
   entry at the settings default (45m) and shows "Logged 45m".

### Screen-state evidence

| Screen | Loading | Empty | Error | Validation | Success |
| --- | --- | --- | --- | --- | --- |
| Today (`today_screen.dart`) | `_serviceTodayList` spinner, "Loading today's entries…"; `ScreenBody` | `EmptyState` "Nothing logged yet" | entries error panel + Retry, `_WeekReportError` + retry | `QuickCaptureBar` description/category/person/duration; outcome dialog | "Logged Xm" with Undo, entry/outcome snacks |
| Log (`log_screen.dart`) | `state.logLoading` spinner | filter-aware `EmptyState` + Clear filters | `state.logError` + Retry | edit/split dialogs validators | entry updated/deleted/copied snacks |
| Initiatives (`initiatives_screen.dart`) | taxonomy spinner, report pending text | no-category and no-project `EmptyState`s | `_InlineError` for taxonomy/report | project dialog validators | "Project created" snack |
| Initiative detail (`initiative_detail_screen.dart`) | new `LoadingView` while initiatives load | "Initiative not found" | new `ErrorView` + retry | note/entry dialogs | entry/note/status snacks |
| Project detail (`project_detail_screen.dart`) | notes/milestones/timeline spinners | empty notes/milestones/timeline `EmptyState`s | `_InlineError` + retry per section | note/milestone/project validators | note/milestone/status snacks |
| Support (`support_screen.dart`) | `state.supportLoading` spinner | "No support logged in this period" | `supportError` panel + retry | support dialog validators | saved/updated/deleted snacks |
| Check-ins (`checkins_screen.dart`) | list loading spinner, `ScreenBody` | no check-ins `EmptyState` | list error `EmptyState` + retry | check-in dialog validators | create navigates, delete snack |
| Check-in detail (`checkin_detail_screen.dart`) | `LoadingView` | not-found `EmptyState` | error `EmptyState` + Retry, generation error | summary/finalize guards | generated/saved/finalized snacks |
| Review (`review_screen.dart`) | `_saving` spinner | empty-period `EmptyState` | `reviewError` + retry, save `FormError` | `validateReviewPeriod` | save navigates to detail |
| Settings (`settings_screen.dart`) | `ScreenBody`, preferences/AI linear progress | panel empty states | preferences/AI/backup errors | time/AI field validators | save/theme/density/backup snacks |
| Login (`login_screen.dart`) | config spinner | n/a (form screen) | config error + "Retry connection", `auth-error` | local/register/bootstrap checks | sign-in/registration navigates; OIDC notice |

### `make check`

Run from `/workspaces/wdid`: exit 0. `go vet`, `flutter analyze` ("No issues
found"), proto regeneration check, Go tests, and all 247 Flutter tests pass
(including the 18 new `ui_polish_test.dart` tests).

- Manual verification (2026-10-24): opening the built app exposed a pre-existing
  auth-gate defect — the router had no guard, so `/today` rendered with no
  session and every service call failed with `missing or malformed bearer
  token`; the login screen was only reachable by typing `/login`. Fixed in
  `web/lib/routing/app_router.dart` (unauthenticated routes redirect to
  `/login`, signed-in visits to `/login` redirect to `/today`), data loading is
  deferred until a session exists (`web/lib/app.dart`,
  `web/lib/state/auth_state.dart`), and `web/test/auth_gate_test.dart` covers
  the gate. `make check` passes with 252 Flutter tests.
- Human sign-off recorded 2026-10-24: the user reviewed the running app and
  asked for this issue to be marked done. The visual sign-off item is resolved;
  no token or focus-ring tuning was requested.


