import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/screens/log_screen.dart';
import 'package:wdid_web/screens/settings_screen.dart';
import 'package:wdid_web/screens/today_screen.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/widgets/app_shell.dart';
import 'package:wdid_web/widgets/forms/dialog_frame.dart';
import 'package:wdid_web/widgets/quick_capture_bar.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_timer_api.dart';

const _viewport = Size(1600, 1800);

Category _category(
  String id,
  String name, {
  CategoryRole role = CategoryRole.initiative,
}) => Category(
  id: id,
  name: name,
  role: role,
  createdAt: DateTime.utc(2026, 10, 23),
  updatedAt: DateTime.utc(2026, 10, 23),
);

Subcategory _subcategory(String id, String categoryId, String name) =>
    Subcategory(
      id: id,
      categoryId: categoryId,
      name: name,
      createdAt: DateTime.utc(2026, 10, 23),
      updatedAt: DateTime.utc(2026, 10, 23),
    );

Finder _fieldWithHint(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

Finder _fieldWithLabel(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

/// Confirms the finder really owns keyboard focus, so the regression cannot
/// pass merely because the field was never focused.
void _expectFocused(WidgetTester tester, Finder field) {
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  expect(editable.focusNode.hasFocus, isTrue);
}

Future<void> _focusField(WidgetTester tester, Finder field) async {
  await tester.showKeyboard(field);
  await tester.pump();
  _expectFocused(tester, field);
}

/// Sends the keys the shortcut layer listens for, with the characters a person
/// would actually type so both the logical key and the character are realistic.
Future<void> _typeShortcutCharacters(WidgetTester tester) async {
  const keys = [
    (LogicalKeyboardKey.keyG, 'g'),
    (LogicalKeyboardKey.keyT, 't'),
    (LogicalKeyboardKey.keyN, 'n'),
    (LogicalKeyboardKey.keyS, 's'),
    (LogicalKeyboardKey.slash, '/'),
  ];
  for (final (key, character) in keys) {
    await tester.sendKeyEvent(key, character: character);
    await tester.pump();
  }
  await tester.sendKeyEvent(
    LogicalKeyboardKey.slash,
    character: '?',
    physicalKey: PhysicalKeyboardKey.slash,
  );
  await tester.pump();
}

/// Asserts that typing the shortcut characters changed none of the three
/// observable outcomes the ticket cares about: dialogs, navigation, the timer.
Future<void> _expectNoShortcutEffects(
  WidgetTester tester,
  AppState state, {
  required Finder screen,
}) async {
  expect(state.activeTimer, isNull, reason: 'no timer should start or stop');
  expect(
    state.searchFocusRequest.value,
    0,
    reason: 'no shortcut should ask Log to focus search',
  );
  expect(find.text('Keyboard shortcuts'), findsNothing);
  expect(find.text('Log support'), findsNothing);
  expect(find.byType(Dialog), findsNothing);
  expect(
    screen,
    findsOneWidget,
    reason: 'the current screen should not change',
  );
}

void main() {
  Future<AppState> pumpApp(
    WidgetTester tester, {
    String route = '/today',
    FakeEntryApi? entryApi,
    FakeTimerApi? timerApi,
  }) async {
    tester.view.physicalSize = _viewport;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
    });

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: route,
        categoryApiBuilder: (_) => FakeCategoryApi(
          categories: [
            _category('cat-1', 'Initiatives'),
            _category('cat-s', 'Support', role: CategoryRole.support),
          ],
          subcategories: [
            _subcategory('sub-1', 'cat-1', 'Billing migration'),
            _subcategory('mode-s', 'cat-s', 'Unblock'),
          ],
        ),
        settingsApiBuilder: (_) => FakeSettingsApi(),
        entryApiBuilder: (_) => entryApi ?? FakeEntryApi(),
        timerApiBuilder: (_) => timerApi ?? FakeTimerApi(),
      ),
    );
    await tester.pumpAndSettle();
    return AppStateScope.read(tester.element(find.byType(AppShell)));
  }

  group('typing in a text field fires no shortcut', () {
    testWidgets('Today timer description', (tester) async {
      final state = await pumpApp(tester);
      await _focusField(tester, _fieldWithHint('What are you working on?'));

      await _typeShortcutCharacters(tester);
      await tester.pumpAndSettle();

      await _expectNoShortcutEffects(
        tester,
        state,
        screen: find.byType(TodayScreen),
      );
    });

    testWidgets('Today Quick Capture description', (tester) async {
      final state = await pumpApp(tester);
      await _focusField(tester, _fieldWithHint('What did you do?'));

      await _typeShortcutCharacters(tester);
      await tester.pumpAndSettle();

      await _expectNoShortcutEffects(
        tester,
        state,
        screen: find.byType(TodayScreen),
      );
    });

    testWidgets('Today Quick Capture person', (tester) async {
      final state = await pumpApp(tester);

      // The person field only renders once the selected category is support.
      final categoryDropdown = find
          .descendant(
            of: find.byType(QuickCaptureBar),
            matching: find.byType(DropdownButton<String>),
          )
          .first;
      await tester.tap(categoryDropdown);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Support').last);
      await tester.pumpAndSettle();

      final person = find.descendant(
        of: find.byType(QuickCaptureBar),
        matching: _fieldWithHint('Who did you support?'),
      );
      await _focusField(tester, person);

      await _typeShortcutCharacters(tester);
      await tester.pumpAndSettle();

      await _expectNoShortcutEffects(
        tester,
        state,
        screen: find.byType(TodayScreen),
      );
    });

    testWidgets('Log search', (tester) async {
      final state = await pumpApp(tester, route: '/log');
      await _focusField(tester, _fieldWithHint('Search entries…  /'));

      await _typeShortcutCharacters(tester);
      await tester.pumpAndSettle();

      await _expectNoShortcutEffects(
        tester,
        state,
        screen: find.byType(LogScreen),
      );
    });

    testWidgets('the inline Log entry form', (tester) async {
      final state = await pumpApp(tester, route: '/log');

      await tester.tap(find.text('Add entry').first);
      await tester.pumpAndSettle();
      await _focusField(tester, _fieldWithLabel('Description'));

      await _typeShortcutCharacters(tester);
      await tester.pumpAndSettle();

      await _expectNoShortcutEffects(
        tester,
        state,
        screen: find.byType(LogScreen),
      );
      // The inline form stays open; it is not replaced by a dialog.
      expect(find.text('New entry'), findsOneWidget);
    });

    testWidgets('the support dialog', (tester) async {
      final state = await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS, character: 's');
      await tester.pumpAndSettle();
      expect(find.byType(DialogFrame), findsOneWidget);

      final person = find.descendant(
        of: find.byType(DialogFrame),
        matching: _fieldWithLabel('Person'),
      );
      await _focusField(tester, person);

      await _typeShortcutCharacters(tester);
      await tester.pumpAndSettle();

      expect(state.activeTimer, isNull);
      expect(state.searchFocusRequest.value, 0);
      expect(find.text('Keyboard shortcuts'), findsNothing);
      expect(find.text('New entry'), findsNothing);
      // Only the support form remains open.
      expect(find.byType(DialogFrame), findsOneWidget);
      expect(find.byType(TodayScreen), findsOneWidget);
    });

    testWidgets('Settings fields', (tester) async {
      final state = await pumpApp(tester, route: '/settings');

      for (final label in const [
        'Timezone',
        'Daily target',
        'Long timer prompt',
        'Default duration',
        'Base URL',
        'Model',
      ]) {
        final field = _fieldWithLabel(label);
        await tester.scrollUntilVisible(
          field,
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await _focusField(tester, field);

        await _typeShortcutCharacters(tester);
        await tester.pumpAndSettle();

        await _expectNoShortcutEffects(
          tester,
          state,
          screen: find.byType(SettingsScreen),
        );
      }
    });
  });

  group('shortcuts still work outside a text field', () {
    testWidgets('T starts the timer', (tester) async {
      final state = await pumpApp(tester);
      state.lastCategoryId = 'cat-1';

      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.activeTimer, isNotNull);
    });

    testWidgets('N opens a new entry', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.text('New entry'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New entry'), findsNothing);
    });

    testWidgets('Escape still closes the shortcut reference', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.slash,
        character: '?',
        physicalKey: PhysicalKeyboardKey.slash,
      );
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsNothing);
    });
  });
}
