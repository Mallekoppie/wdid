import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/category_api.dart';
import 'package:wdid_web/data/entry_api.dart';
import 'package:wdid_web/data/milestone_api.dart';
import 'package:wdid_web/data/note_api.dart';
import 'package:wdid_web/data/summary_api.dart';
import 'package:wdid_web/models/milestone.dart';
import 'package:wdid_web/models/note.dart';
import 'package:wdid_web/models/period_report.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/stat_tile.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_milestone_api.dart';
import 'fake_note_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

Category category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
  bool archived = false,
}) {
  return Category(
    id: id,
    name: name,
    role: role,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

Subcategory project(
  String id, {
  String categoryId = 'cat-init',
  required String name,
  String description = '',
  SubcategoryStatus status = SubcategoryStatus.active,
  int progress = 0,
  String targetOutcome = '',
  bool archived = false,
}) {
  return Subcategory(
    id: id,
    categoryId: categoryId,
    name: name,
    description: description,
    status: status,
    progress: progress,
    targetOutcome: targetOutcome,
    archived: archived,
    createdAt: DateTime.utc(2026, 10, 23),
    updatedAt: DateTime.utc(2026, 10, 23),
  );
}

WorkEntry workEntry({
  required String id,
  String categoryId = 'cat-init',
  String subcategoryId = 'sub-invoice',
  String description = '',
  String outcome = '',
  List<String> people = const [],
  required DateTime startedAt,
  int minutes = 30,
}) {
  return WorkEntry(
    id: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    people: people,
    startedAt: startedAt,
    endedAt: startedAt.add(Duration(minutes: minutes)),
    minutes: minutes,
    localDate: startedAt.toIso8601String().substring(0, 10),
    createdAt: startedAt,
    updatedAt: startedAt,
  );
}

PeriodReport reportWithProject({
  int minutes = 120,
  int entryCount = 2,
  String lastActivityDate = '2026-10-22',
  String lastActivityDescription = 'Backfill review',
  int milestoneDone = 0,
  int milestoneTotal = 0,
}) {
  return PeriodReport(
    fromDate: '2026-10-01',
    toDate: '2026-10-23',
    totalMinutes: minutes,
    entryCount: entryCount,
    categories: [
      CategoryAllocation(
        categoryId: 'cat-init',
        name: 'Initiatives',
        role: CategoryRole.initiative,
        minutes: minutes,
        entryCount: entryCount,
      ),
    ],
    subcategories: [
      SubcategoryAllocation(
        subcategoryId: 'sub-invoice',
        categoryId: 'cat-init',
        name: 'Invoice pipeline',
        minutes: minutes,
        entryCount: entryCount,
        lastActivityDate: lastActivityDate,
        lastActivityDescription: lastActivityDescription,
      ),
    ],
    milestoneProgress: [
      if (milestoneTotal > 0)
        MilestoneProgress(
          subcategoryId: 'sub-invoice',
          total: milestoneTotal,
          done: milestoneDone,
        ),
    ],
  );
}

Milestone milestone(
  String id, {
  String title = 'Plan the backfill',
  String dueDate = '',
  bool done = false,
  String subcategoryId = 'sub-invoice',
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime.utc(2026, 10, 20, 9);
  return Milestone(
    id: id,
    subcategoryId: subcategoryId,
    title: title,
    dueDate: dueDate,
    done: done,
    createdAt: created,
    updatedAt: created,
  );
}

FakeCategoryApi projectTaxonomy({bool archived = false}) {
  return FakeCategoryApi(
    categories: [
      category('cat-init', 'Initiatives'),
      category('cat-support', 'Support', role: CategoryRole.support),
    ],
    subcategories: [
      project(
        'sub-invoice',
        name: 'Invoice pipeline',
        progress: 64,
        targetOutcome: 'Invoice generation under 5 minutes',
        archived: archived,
      ),
      project('sub-spike', name: 'Dependency spike'),
    ],
  );
}

Future<void> pumpDetail(
  WidgetTester tester, {
  required String route,
  FakeCategoryApi? categoryApi,
  FakeEntryApi? entryApi,
  FakeSummaryApi? summaryApi,
  FakeNoteApi? noteApi,
  FakeMilestoneApi? milestoneApi,
  bool settle = true,
}) async {
  tester.view.physicalSize = const Size(1400, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    WdidApp(
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: route,
      categoryApiBuilder: (_) => categoryApi ?? projectTaxonomy(),
      entryApiBuilder: (_) =>
          entryApi ??
          FakeEntryApi(
            entries: [
              workEntry(
                id: 'entry-old',
                description: 'Backfill script',
                startedAt: DateTime.utc(2026, 10, 20, 9),
                minutes: 60,
              ),
              workEntry(
                id: 'entry-new',
                description: 'Backfill review',
                outcome: 'Script runs against staging',
                people: const ['Priya'],
                startedAt: DateTime.utc(2026, 10, 22, 9),
                minutes: 60,
              ),
            ],
          ),
      summaryApiBuilder: (_) =>
          summaryApi ?? FakeSummaryApi(report: reportWithProject()),
      noteApiBuilder: noteApi == null ? null : (_) => noteApi,
      milestoneApiBuilder: milestoneApi == null ? null : (_) => milestoneApi,
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  testWidgets('opens a project from the portfolio', (tester) async {
    await pumpDetail(tester, route: '/initiatives');

    await tester.tap(find.text('Invoice pipeline'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to initiatives'), findsOneWidget);
    expect(find.text('Invoice pipeline'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a direct link shows the project header', (tester) async {
    await pumpDetail(tester, route: '/initiatives/sub-invoice');

    expect(find.text('Invoice pipeline'), findsWidgets);
    expect(find.text('Initiatives'), findsWidgets);
    expect(find.text('Active'), findsOneWidget);
    expect(find.text('64%'), findsOneWidget);
    expect(find.text('Invoice generation under 5 minutes'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logs time against the project', (tester) async {
    final entryApi = FakeEntryApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Backfill script skeleton');
    await tester.enterText(fields.at(1), 'Script runs against staging');
    await tester.enterText(fields.at(2), '30');

    await tester.tap(find.widgetWithText(FilledButton, 'Save entry'));
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(1));
    expect(entryApi.drafts.single.categoryId, 'cat-init');
    expect(entryApi.drafts.single.subcategoryId, 'sub-invoice');
    expect(entryApi.drafts.single.description, 'Backfill script skeleton');
    expect(entryApi.drafts.single.outcome, 'Script runs against staging');
    expect(entryApi.drafts.single.minutes, 30);
    expect(find.text('Backfill script skeleton'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('logs project time for several optional people', (tester) async {
    final entryApi = FakeEntryApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'Backfill script skeleton');
    await tester.enterText(fields.at(2), '45');
    await tester.enterText(fields.at(3), 'Priya');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.enterText(fields.at(3), 'Sam');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save entry'));
    await tester.pumpAndSettle();

    expect(entryApi.drafts, hasLength(1));
    expect(entryApi.drafts.single.people, ['Priya', 'Sam']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report shows project-scoped totals and interactions', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      summaryApi: FakeSummaryApi(
        report: reportWithProject(minutes: 150, entryCount: 3),
      ),
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    // The total comes from the report allocation, not the two timeline rows.
    expect(find.text('2h 30m'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Backfill review'), findsWidgets);
    expect(find.text('1 interaction'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Script runs against staging'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived project is read-only until restored', (
    tester,
  ) async {
    final categories = projectTaxonomy(archived: true);
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: categories,
    );

    expect(
      find.text('This project is archived and read-only.'),
      findsOneWidget,
    );
    expect(find.text('Log time'), findsNothing);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();

    expect(
      categories.subcategories
          .firstWhere((item) => item.id == 'sub-invoice')
          .archived,
      isFalse,
    );
    expect(find.text('This project is archived and read-only.'), findsNothing);
    expect(find.text('Log time'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty timeline state', (tester) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: FakeEntryApi(),
    );

    expect(find.text('No time logged yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries the timeline after a service failure', (tester) async {
    final entryApi = FakeEntryApi()
      ..listFailure = const EntryFailure('The service is unreachable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    expect(find.text('The service is unreachable.'), findsOneWidget);

    entryApi.listFailure = null;
    entryApi.entries.addAll([
      workEntry(
        id: 'entry-1',
        description: 'Backfill script',
        startedAt: DateTime.utc(2026, 10, 20, 9),
      ),
    ]);
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Backfill script'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries the report after a service failure', (tester) async {
    final summary = FakeSummaryApi(report: reportWithProject())
      ..failure = const SummaryFailure('The report is unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      summaryApi: summary,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();
    expect(find.text('The report is unavailable.'), findsOneWidget);

    summary.failure = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('2h'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed report hides the interactions it cannot date', (
    tester,
  ) async {
    final summary = FakeSummaryApi(report: reportWithProject())
      ..failure = const SummaryFailure('The report is unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      summaryApi: summary,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('The report is unavailable.'), findsOneWidget);
    expect(find.text('Report unavailable'), findsOneWidget);
    // The entry named Priya falls inside the quarter, but without a report
    // there is no period to filter against; it must not be shown as if it
    // were this quarter's interaction.
    expect(find.text('Priya'), findsNothing);
    expect(find.text('In period review'), findsNothing);
    expect(find.textContaining('No people were named'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('handles an unknown project id', (tester) async {
    await pumpDetail(tester, route: '/initiatives/missing');

    expect(find.text('Project not found'), findsOneWidget);
    expect(find.text('Back to initiatives'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a retryable state when the taxonomy fails', (
    tester,
  ) async {
    final failing = FakeCategoryApi()
      ..failure = const CategoryFailure('The taxonomy is unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/missing',
      categoryApi: failing,
    );

    expect(find.text('Could not load the projects'), findsOneWidget);
    expect(find.text('The taxonomy is unavailable.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a loading state while the taxonomy loads', (tester) async {
    final gate = Completer<void>();
    final categories = projectTaxonomy()..gate = gate;

    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: categories,
      settle: false,
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();

    expect(find.text('Invoice pipeline'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates the log-time form before saving', (tester) async {
    final entryApi = FakeEntryApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Log time'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save entry'));
    await tester.pumpAndSettle();

    expect(find.text('A short description is required.'), findsOneWidget);
    expect(entryApi.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens an archived project from the portfolio', (tester) async {
    final categories = projectTaxonomy(archived: true);
    await pumpDetail(tester, route: '/initiatives', categoryApi: categories);

    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invoice pipeline'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Back to initiatives'), findsOneWidget);
    expect(
      find.text('This project is archived and read-only.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report only lists interactions from its period', (
    tester,
  ) async {
    final entryApi = FakeEntryApi(
      entries: [
        workEntry(
          id: 'entry-in',
          description: 'In period review',
          people: const ['Priya'],
          startedAt: DateTime.utc(2026, 10, 22, 9),
        ),
        workEntry(
          id: 'entry-out',
          description: 'Old review',
          people: const ['Sam'],
          startedAt: DateTime.utc(2026, 8, 1, 9),
        ),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('In period review'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);
    expect(find.text('Old review'), findsNothing);
    expect(find.text('Sam'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report surfaces a timeline failure instead of empty', (
    tester,
  ) async {
    final entryApi = FakeEntryApi()
      ..listFailure = const EntryFailure('The service is unreachable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      entryApi: entryApi,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(
      find.text('This project’s entries could not be loaded.'),
      findsOneWidget,
    );
    expect(find.text('The service is unreachable.'), findsOneWidget);
    expect(find.textContaining('No people were named'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the timeline lists the project entries newest first', (
    tester,
  ) async {
    await pumpDetail(tester, route: '/initiatives/sub-invoice');

    expect(find.text('Backfill review'), findsOneWidget);
    expect(find.text('Backfill script'), findsOneWidget);
    expect(find.text('Script runs against staging'), findsOneWidget);
    expect(find.text('Priya'), findsOneWidget);

    final newest = tester.getTopLeft(find.text('Backfill review')).dy;
    final oldest = tester.getTopLeft(find.text('Backfill script')).dy;
    expect(newest, lessThan(oldest));
    expect(tester.takeException(), isNull);
  });

  testWidgets('lists project notes newest first and creates a new one', (
    tester,
  ) async {
    final noteApi = FakeNoteApi(
      notes: [
        projectNote(
          'note-old',
          text: 'Rollback plan needs a rehearsal.',
          createdAt: DateTime.utc(2026, 10, 18, 9),
        ),
        projectNote(
          'note-new',
          text: 'Cutover window booked.',
          createdAt: DateTime.utc(2026, 10, 22, 9),
        ),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: noteApi,
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Cutover window booked.'), findsOneWidget);
    expect(find.text('Rollback plan needs a rehearsal.'), findsOneWidget);
    final newest = tester.getTopLeft(find.text('Cutover window booked.')).dy;
    final oldest = tester
        .getTopLeft(find.text('Rollback plan needs a rehearsal.'))
        .dy;
    expect(newest, lessThan(oldest));
    expect(noteApi.lastSubcategoryId, 'sub-invoice');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add note').first);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Decisions, context, or things to revisit…',
      ),
      'Backfill is stable enough to track.',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
    await tester.pumpAndSettle();

    expect(noteApi.drafts, hasLength(1));
    expect(noteApi.drafts.single.initiativeId, 'sub-invoice');
    expect(noteApi.drafts.single.date, isoDate(DateTime.now()));
    expect(noteApi.drafts.single.text, 'Backfill is stable enough to track.');
    expect(find.text('Backfill is stable enough to track.'), findsWidgets);
    expect(find.text('Note added'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits an existing project note', (tester) async {
    final noteApi = FakeNoteApi(
      notes: [
        projectNote(
          'note-1',
          text: 'First version.',
          createdAt: DateTime.utc(2026, 10, 22, 9),
        ),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: noteApi,
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit note'));
    await tester.pumpAndSettle();

    final field = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText ==
              'Decisions, context, or things to revisit…',
    );
    await tester.enterText(field, 'Second version.');
    await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
    await tester.pumpAndSettle();

    expect(noteApi.updateCalls, 1);
    expect(noteApi.notes.single.text, 'Second version.');
    expect(find.text('Second version.'), findsWidgets);
    expect(find.text('First version.'), findsNothing);
    expect(find.text('Note updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletes a project note after confirmation', (tester) async {
    final noteApi = FakeNoteApi(
      notes: [
        projectNote(
          'note-1',
          text: 'Temporary decision.',
          createdAt: DateTime.utc(2026, 10, 22, 9),
        ),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: noteApi,
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete note'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(noteApi.deleteCalls, 1);
    expect(noteApi.notes, isEmpty);
    expect(find.text('Temporary decision.'), findsNothing);
    expect(find.text('No notes yet'), findsOneWidget);
    expect(find.text('Note deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty notes state', (tester) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: FakeNoteApi(),
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('No notes yet'), findsOneWidget);
    expect(
      find.text('Capture decisions and context while they are fresh.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a loading state while project notes load', (tester) async {
    final gate = Completer<List<Note>>();
    final noteApi = FakeNoteApi()..projectGate = gate;
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: noteApi,
      settle: false,
    );

    // Let the taxonomy, entries and report settle while notes stay in flight.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.text('Notes'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete([
      projectNote(
        'note-1',
        text: 'Loaded project note.',
        createdAt: DateTime.utc(2026, 10, 22, 9),
      ),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Loaded project note.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries notes after a service failure', (tester) async {
    final noteApi = FakeNoteApi()
      ..listFailure = const NoteFailure('The notes are unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: noteApi,
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    expect(find.text('The notes are unavailable.'), findsOneWidget);

    noteApi.listFailure = null;
    noteApi.notes.add(
      projectNote(
        'note-1',
        text: 'Recovered note.',
        createdAt: DateTime.utc(2026, 10, 22, 9),
      ),
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Recovered note.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates an empty note before saving', (tester) async {
    final noteApi = FakeNoteApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      noteApi: noteApi,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Add note').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save note'));
    await tester.pumpAndSettle();

    expect(find.text('Write a note first.'), findsOneWidget);
    expect(noteApi.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived project cannot change its notes', (tester) async {
    final noteApi = FakeNoteApi(
      notes: [
        projectNote(
          'note-1',
          text: 'Historical decision.',
          createdAt: DateTime.utc(2026, 10, 22, 9),
        ),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: projectTaxonomy(archived: true),
      noteApi: noteApi,
    );

    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();

    expect(find.text('Historical decision.'), findsOneWidget);
    expect(find.text('Add note'), findsNothing);
    expect(find.byTooltip('Edit note'), findsNothing);
    expect(find.byTooltip('Delete note'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('lists milestones and creates one from the project detail', (
    tester,
  ) async {
    final milestoneApi = FakeMilestoneApi(
      milestones: [
        milestone(
          'milestone-1',
          title: 'Plan the backfill',
          dueDate: '2026-10-25',
        ),
        milestone('milestone-2', title: 'Ship to production', done: true),
      ],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();

    expect(milestoneApi.lastSubcategoryId, 'sub-invoice');
    expect(find.text('Plan the backfill'), findsOneWidget);
    expect(find.text('Ship to production'), findsOneWidget);
    expect(find.text('Due 25 Oct'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add milestone'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Rehearse the rollback');
    await tester.tap(find.widgetWithText(FilledButton, 'Save milestone'));
    await tester.pumpAndSettle();

    expect(milestoneApi.drafts, hasLength(1));
    expect(milestoneApi.drafts.single.subcategoryId, 'sub-invoice');
    expect(milestoneApi.drafts.single.title, 'Rehearse the rollback');
    expect(milestoneApi.drafts.single.dueDate, '');
    expect(find.text('Rehearse the rollback'), findsOneWidget);
    expect(find.text('Milestone added'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('marks a milestone done and not done', (tester) async {
    final milestoneApi = FakeMilestoneApi(
      milestones: [milestone('milestone-1', title: 'Plan the backfill')],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(milestoneApi.updateCalls, 1);
    expect(milestoneApi.milestones.single.done, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(milestoneApi.updateCalls, 2);
    expect(milestoneApi.milestones.single.done, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits an existing milestone', (tester) async {
    final milestoneApi = FakeMilestoneApi(
      milestones: [milestone('milestone-1', title: 'First plan')],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit milestone'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Second plan');
    await tester.tap(find.widgetWithText(FilledButton, 'Save milestone'));
    await tester.pumpAndSettle();

    expect(milestoneApi.updateCalls, 1);
    expect(milestoneApi.milestones.single.title, 'Second plan');
    expect(find.text('Second plan'), findsOneWidget);
    expect(find.text('First plan'), findsNothing);
    expect(find.text('Milestone updated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deletes a milestone after confirmation', (tester) async {
    final milestoneApi = FakeMilestoneApi(
      milestones: [milestone('milestone-1', title: 'Temporary checkpoint')],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete milestone'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(milestoneApi.deleteCalls, 1);
    expect(milestoneApi.milestones, isEmpty);
    expect(find.text('Temporary checkpoint'), findsNothing);
    expect(find.text('No milestones yet'), findsOneWidget);
    expect(find.text('Milestone deleted'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows an empty milestones state', (tester) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: FakeMilestoneApi(),
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();

    expect(find.text('No milestones yet'), findsOneWidget);
    expect(find.text('Add milestone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows a loading state while milestones load', (tester) async {
    final gate = Completer<List<Milestone>>();
    final milestoneApi = FakeMilestoneApi()..listGate = gate;
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
      settle: false,
    );

    // Let the taxonomy, entries, notes and report settle while milestones stay
    // in flight.
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.tap(find.text('Milestones'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete([milestone('milestone-1', title: 'Loaded milestone')]);
    await tester.pumpAndSettle();

    expect(find.text('Loaded milestone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retries milestones after a service failure', (tester) async {
    final milestoneApi = FakeMilestoneApi()
      ..listFailure = const MilestoneFailure('The milestones are unavailable.');
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();
    expect(find.text('The milestones are unavailable.'), findsOneWidget);

    milestoneApi.listFailure = null;
    milestoneApi.milestones.add(
      milestone('milestone-1', title: 'Recovered milestone'),
    );
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Recovered milestone'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('validates an empty milestone title before saving', (
    tester,
  ) async {
    final milestoneApi = FakeMilestoneApi();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add milestone'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save milestone'));
    await tester.pumpAndSettle();

    expect(find.text('Milestone title is required.'), findsOneWidget);
    expect(milestoneApi.drafts, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report shows how many milestones are complete', (
    tester,
  ) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      summaryApi: FakeSummaryApi(
        report: reportWithProject(milestoneDone: 2, milestoneTotal: 5),
      ),
      milestoneApi: FakeMilestoneApi(),
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    expect(find.text('Milestones'), findsWidgets);
    expect(find.text('2 of 5 complete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived project cannot change its milestones', (
    tester,
  ) async {
    final milestoneApi = FakeMilestoneApi(
      milestones: [milestone('milestone-1', title: 'Historical checkpoint')],
    );
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: projectTaxonomy(archived: true),
      milestoneApi: milestoneApi,
    );

    await tester.tap(find.text('Milestones'));
    await tester.pumpAndSettle();

    expect(find.text('Historical checkpoint'), findsOneWidget);
    expect(find.text('Add milestone'), findsNothing);
    expect(find.byTooltip('Edit milestone'), findsNothing);
    expect(find.byTooltip('Delete milestone'), findsNothing);
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).onChanged, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edits a project from the detail header', (tester) async {
    final categories = projectTaxonomy();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: categories,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();

    expect(find.text('Edit project'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(
      tester.widget<TextFormField>(fields.at(0)).controller!.text,
      'Invoice pipeline',
    );
    expect(
      tester.widget<TextFormField>(fields.at(2)).controller!.text,
      'Invoice generation under 5 minutes',
    );

    await tester.enterText(fields.at(2), 'Invoices under two minutes');
    tester.widget<Slider>(find.byType(Slider)).onChanged!(80);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    final saved = categories.subcategories.firstWhere(
      (item) => item.id == 'sub-invoice',
    );
    expect(saved.targetOutcome, 'Invoices under two minutes');
    expect(saved.progress, 80);
    expect(find.text('Invoices under two minutes'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    expect(find.text('Project updated · Invoice pipeline'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an archived project offers no edit action', (tester) async {
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: projectTaxonomy(archived: true),
    );

    expect(find.text('Restore'), findsOneWidget);
    expect(find.text('Edit'), findsNothing);
    expect(find.widgetWithText(OutlinedButton, 'Edit'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the report shows progress and reflects an edit', (tester) async {
    final categories = projectTaxonomy();
    await pumpDetail(
      tester,
      route: '/initiatives/sub-invoice',
      categoryApi: categories,
    );

    await tester.tap(find.text('Report'));
    await tester.pumpAndSettle();

    StatTile progressTile() => tester.widget<StatTile>(
      find.widgetWithText(StatTile, 'Progress'),
    );
    expect(progressTile().value, '64%');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit'));
    await tester.pumpAndSettle();
    tester.widget<Slider>(find.byType(Slider)).onChanged!(90);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    expect(progressTile().value, '90%');
    expect(
      categories.subcategories
          .firstWhere((item) => item.id == 'sub-invoice')
          .progress,
      90,
    );
    expect(tester.takeException(), isNull);
  });
}

Note projectNote(
  String id, {
  required String text,
  DateTime? createdAt,
  String subcategoryId = 'sub-invoice',
}) {
  return Note(
    id: id,
    date: '2026-10-22',
    initiativeId: subcategoryId,
    text: text,
    createdAt: createdAt ?? DateTime.utc(2026, 10, 22, 9),
  );
}
