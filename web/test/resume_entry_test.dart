import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/timer_api.dart';
import 'package:wdid_web/models/link_ref.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/work_entry_row.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_timer_api.dart';

Category category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
  bool archived = false,
}) => Category(
  id: id,
  name: name,
  role: role,
  archived: archived,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

Subcategory subcategory(
  String id,
  String categoryId,
  String name, {
  bool archived = false,
}) => Subcategory(
  id: id,
  categoryId: categoryId,
  name: name,
  archived: archived,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

WorkEntry workEntry({
  String id = 'entry-1',
  String categoryId = 'cat-1',
  String subcategoryId = 'sub-1',
  String description = 'Backfill script',
  String outcome = 'Script deployed',
  List<String> people = const [],
  List<String> tags = const ['backend'],
  List<LinkRef> links = const [
    LinkRef(label: 'Design doc', url: 'https://example.com/doc'),
  ],
}) {
  final now = DateTime.now();
  final started = now.subtract(const Duration(minutes: 30));
  return WorkEntry(
    id: id,
    categoryId: categoryId,
    subcategoryId: subcategoryId,
    description: description,
    outcome: outcome,
    people: people,
    tags: tags,
    links: links,
    startedAt: started.toUtc(),
    endedAt: started.add(const Duration(minutes: 30)).toUtc(),
    minutes: 30,
    localDate: isoDate(now),
    createdAt: now.toUtc(),
    updatedAt: now.toUtc(),
  );
}

Future<void> pumpToday(
  WidgetTester tester, {
  FakeTimerApi? timerApi,
  FakeEntryApi? entryApi,
  FakeCategoryApi? categoryApi,
}) async {
  tester.view.physicalSize = const Size(1400, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    WdidApp(
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: '/today',
      categoryApiBuilder: (_) =>
          categoryApi ??
          FakeCategoryApi(
            categories: [category('cat-1', 'Initiatives')],
            subcategories: [subcategory('sub-1', 'cat-1', 'Billing migration')],
          ),
      settingsApiBuilder: (_) => FakeSettingsApi(),
      entryApiBuilder: (_) => entryApi ?? FakeEntryApi(),
      timerApiBuilder: timerApi == null ? null : (_) => timerApi,
    ),
  );
  await tester.pumpAndSettle();

  // Dispose the app so its poll ticker does not outlive the test.
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });
}

Finder todayResumeButton() => find.descendant(
  of: find.byType(WorkEntryRow),
  matching: find.byType(IconButton),
);

Future<void> pumpLog(
  WidgetTester tester, {
  required FakeTimerApi timerApi,
  required FakeEntryApi entryApi,
  FakeCategoryApi? categoryApi,
}) async {
  tester.view.physicalSize = const Size(1600, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    WdidApp(
      authApi: FakeAuthApi(),
      initialSession: signedInSession(),
      initialRoute: '/log',
      categoryApiBuilder: (_) =>
          categoryApi ??
          FakeCategoryApi(
            categories: [category('cat-1', 'Initiatives')],
            subcategories: [subcategory('sub-1', 'cat-1', 'Billing migration')],
          ),
      settingsApiBuilder: (_) => FakeSettingsApi(),
      entryApiBuilder: (_) => entryApi,
      timerApiBuilder: (_) => timerApi,
    ),
  );
  await tester.pumpAndSettle();

  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
  });
}

void main() {
  testWidgets('Today Resume starts a timer attributed like the entry', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final entryApi = FakeEntryApi(
      entries: [
        workEntry(
          description: 'Backfill script',
          outcome: 'Script deployed',
          tags: const ['backend'],
          links: const [
            LinkRef(label: 'Design doc', url: 'https://example.com/doc'),
          ],
        ),
      ],
    );
    await pumpToday(tester, timerApi: timerApi, entryApi: entryApi);

    expect(todayResumeButton(), findsOneWidget);
    expect(tester.widget<IconButton>(todayResumeButton()).onPressed, isNotNull);

    await tester.tap(todayResumeButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-1');
    expect(timerApi.lastStartSubcategoryId, 'sub-1');
    expect(timerApi.lastStartDescription, 'Backfill script');
    expect(timerApi.lastStartPeople, isEmpty);
    expect(timerApi.timer!.categoryId, 'cat-1');
    expect(timerApi.timer!.subcategoryId, 'sub-1');
    expect(timerApi.timer!.description, 'Backfill script');
    // Outcome, tags and links have no route into StartTimer.
    expect(timerApi.timer!.description, isNot(contains('Script deployed')));
  });

  testWidgets('Resume carries the people on a support entry', (tester) async {
    final timerApi = FakeTimerApi();
    final entryApi = FakeEntryApi(
      entries: [
        workEntry(
          categoryId: 'cat-s',
          subcategoryId: 'sub-s',
          people: const ['Ada', 'Grace'],
        ),
      ],
    );
    await pumpToday(
      tester,
      timerApi: timerApi,
      entryApi: entryApi,
      categoryApi: FakeCategoryApi(
        categories: [category('cat-s', 'Support', role: CategoryRole.support)],
        subcategories: [subcategory('sub-s', 'cat-s', 'Unblock')],
      ),
    );

    await tester.tap(todayResumeButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-s');
    expect(timerApi.lastStartSubcategoryId, 'sub-s');
    expect(timerApi.lastStartPeople, ['Ada', 'Grace']);
    expect(timerApi.timer!.people, ['Ada', 'Grace']);
  });

  testWidgets('a missing subcategory is dropped and the timer still starts', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final entryApi = FakeEntryApi(
      entries: [workEntry(subcategoryId: 'sub-gone')],
    );
    await pumpToday(tester, timerApi: timerApi, entryApi: entryApi);

    await tester.tap(todayResumeButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-1');
    expect(timerApi.lastStartSubcategoryId, isEmpty);
    expect(timerApi.timer!.categoryId, 'cat-1');
    expect(timerApi.timer!.subcategoryId, isEmpty);
    expect(timerApi.timer!.description, 'Backfill script');
  });

  testWidgets('Resume refuses while a timer runs and leaves it untouched', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final now = DateTime.now().toUtc();
    timerApi.timer = TimerSnapshot(
      categoryId: 'cat-1',
      subcategoryId: 'sub-1',
      description: 'Existing work',
      startedAt: now.subtract(const Duration(minutes: 5)),
      segmentStartedAt: now.subtract(const Duration(minutes: 5)),
    );
    final startedAt = timerApi.timer!.startedAt;
    await pumpToday(
      tester,
      timerApi: timerApi,
      entryApi: FakeEntryApi(entries: [workEntry()]),
    );

    await tester.tap(todayResumeButton());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.startCalls, 0);
    expect(
      timerApi.stopActions,
      isEmpty,
      reason: 'never stop the running timer',
    );
    expect(timerApi.timer!.startedAt, startedAt);
    expect(timerApi.timer!.description, 'Existing work');
    expect(find.text('A timer is already running.'), findsOneWidget);
  });

  testWidgets('Resume is disabled with a tooltip when the category is gone', (
    tester,
  ) async {
    await pumpToday(
      tester,
      timerApi: FakeTimerApi(),
      entryApi: FakeEntryApi(entries: [workEntry(categoryId: 'cat-gone')]),
    );

    expect(todayResumeButton(), findsOneWidget);
    expect(tester.widget<IconButton>(todayResumeButton()).onPressed, isNull);
    expect(
      find.byTooltip("This entry's category no longer exists."),
      findsOneWidget,
    );
  });

  testWidgets(
    'Resume is disabled with a tooltip when the category is archived',
    (tester) async {
      await pumpToday(
        tester,
        timerApi: FakeTimerApi(),
        entryApi: FakeEntryApi(entries: [workEntry()]),
        categoryApi: FakeCategoryApi(
          categories: [category('cat-1', 'Initiatives', archived: true)],
          subcategories: [subcategory('sub-1', 'cat-1', 'Billing migration')],
        ),
      );

      expect(tester.widget<IconButton>(todayResumeButton()).onPressed, isNull);
      expect(
        find.byTooltip("This entry's category is archived."),
        findsOneWidget,
      );
    },
  );

  testWidgets('Resume is disabled when the timer service is unavailable', (
    tester,
  ) async {
    await pumpToday(tester, entryApi: FakeEntryApi(entries: [workEntry()]));

    expect(tester.widget<IconButton>(todayResumeButton()).onPressed, isNull);
    expect(find.byTooltip('The timer service is unavailable.'), findsOneWidget);
  });

  testWidgets('Log row menu Resume starts a timer like the entry', (
    tester,
  ) async {
    final timerApi = FakeTimerApi();
    final entryApi = FakeEntryApi(
      entries: [
        workEntry(
          description: 'Backfill script',
          outcome: 'Script deployed',
          tags: const ['backend'],
          links: const [
            LinkRef(label: 'Design doc', url: 'https://example.com/doc'),
          ],
        ),
      ],
    );
    await pumpLog(tester, timerApi: timerApi, entryApi: entryApi);

    await tester.tap(find.byTooltip('Row actions'));
    await tester.pumpAndSettle();
    expect(find.text('Resume'), findsOneWidget);

    await tester.tap(find.text('Resume'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(timerApi.startCalls, 1);
    expect(timerApi.lastStartCategoryId, 'cat-1');
    expect(timerApi.lastStartSubcategoryId, 'sub-1');
    expect(timerApi.lastStartDescription, 'Backfill script');
    expect(timerApi.timer!.description, 'Backfill script');
    expect(timerApi.timer!.description, isNot(contains('Script deployed')));
  });

  testWidgets(
    'Log Resume is disabled with a tooltip when the category is archived',
    (tester) async {
      final timerApi = FakeTimerApi();
      final entryApi = FakeEntryApi(entries: [workEntry()]);
      await pumpLog(
        tester,
        timerApi: timerApi,
        entryApi: entryApi,
        categoryApi: FakeCategoryApi(
          categories: [category('cat-1', 'Initiatives', archived: true)],
          subcategories: [subcategory('sub-1', 'cat-1', 'Billing migration')],
        ),
      );

      await tester.tap(find.byTooltip('Row actions'));
      await tester.pumpAndSettle();

      final item = tester.widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, 'Resume'),
      );
      expect(item.enabled, isFalse);
      expect(
        find.byTooltip("This entry's category is archived."),
        findsOneWidget,
      );
      expect(timerApi.startCalls, 0);
    },
  );
}
