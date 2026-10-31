import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/auth_api.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/utils/time_utils.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';

Category _category(String id, String name) => Category(
  id: id,
  name: name,
  role: CategoryRole.initiative,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

Subcategory _project(String id, String categoryId, String name) => Subcategory(
  id: id,
  categoryId: categoryId,
  name: name,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

WorkEntry _todayEntry(String id, String description) {
  final started = DateTime.now().subtract(const Duration(minutes: 30));
  return WorkEntry(
    id: id,
    categoryId: 'cat-1',
    subcategoryId: 'sub-1',
    description: description,
    outcome: '',
    people: const [],
    startedAt: started.toUtc(),
    endedAt: started.add(const Duration(minutes: 30)).toUtc(),
    minutes: 30,
    localDate: isoDate(started),
    createdAt: started.toUtc(),
    updatedAt: started.toUtc(),
  );
}

FakeCategoryApi _categoryApi() => FakeCategoryApi(
  categories: [_category('cat-1', 'Initiatives')],
  subcategories: [_project('sub-1', 'cat-1', 'Billing migration')],
);

void main() {
  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeAuthApi auth,
    AuthSession? session,
    String route = '/today',
    FakeEntryApi? entryApi,
    FakeCategoryApi? categoryApi,
  }) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: auth,
        initialSession: session,
        initialRoute: route,
        categoryApiBuilder: categoryApi == null ? null : (_) => categoryApi,
        settingsApiBuilder: (_) => FakeSettingsApi(),
        entryApiBuilder: entryApi == null ? null : (_) => entryApi,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signOut(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();
  }

  Future<void> signInWithPassword(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'test@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'password1',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('the account menu signs out and stays on the login screen', (
    tester,
  ) async {
    final auth = FakeAuthApi();
    await pumpApp(tester, auth: auth, session: signedInSession());

    expect(find.text('Start a timer'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.more_horiz));
    await tester.pumpAndSettle();
    expect(find.text('Sign out'), findsOneWidget);
    expect(find.text('Sign-in screen'), findsNothing);

    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    // Sign out asks for no confirmation and lands on the login screen.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.text('Start a timer'), findsNothing);

    // It stays signed out until the user chooses to sign in again.
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
    expect(find.text('Start a timer'), findsNothing);
  });

  testWidgets('signing in after sign out lands on Today', (tester) async {
    final auth = FakeAuthApi();
    await pumpApp(tester, auth: auth, session: signedInSession());

    await signOut(tester);
    expect(find.text('Start a timer'), findsNothing);

    await signInWithPassword(tester);

    expect(find.text('Start a timer'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('the next account reloads cached data after sign out', (
    tester,
  ) async {
    final auth = FakeAuthApi();
    final entryApi = FakeEntryApi(entries: [_todayEntry('e1', 'First account')]);
    await pumpApp(
      tester,
      auth: auth,
      session: signedInSession(),
      entryApi: entryApi,
      categoryApi: _categoryApi(),
    );

    expect(find.textContaining('First account'), findsOneWidget);

    await signOut(tester);

    // The next account signs in with a different ledger.
    entryApi.entries
      ..clear()
      ..add(_todayEntry('e2', 'Second account'));
    await signInWithPassword(tester);

    expect(find.textContaining('Second account'), findsOneWidget);
    expect(find.textContaining('First account'), findsNothing);
  });
}
