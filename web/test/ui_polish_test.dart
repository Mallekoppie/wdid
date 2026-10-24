import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/taxonomy.dart';
import 'package:wdid_web/models/work_entry.dart';
import 'package:wdid_web/screens/settings_screen.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/theme/app_theme.dart';
import 'package:wdid_web/utils/time_utils.dart';
import 'package:wdid_web/widgets/app_shell.dart';
import 'package:wdid_web/widgets/focus_ring.dart';
import 'package:wdid_web/widgets/nav_rail.dart';
import 'package:wdid_web/widgets/quick_capture_bar.dart';
import 'package:wdid_web/widgets/timer_pill.dart';
import 'package:wdid_web/widgets/work_entry_row.dart';

import 'fake_auth_api.dart';
import 'fake_entry_api.dart';
import 'fake_preferences_api.dart';
import 'fake_timer_api.dart';

const _viewport = Size(1440, 1000);

double _contrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final hi = a > b ? a : b;
  final lo = a > b ? b : a;
  return (hi + 0.05) / (lo + 0.05);
}

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

void main() {
  Future<AppState> pumpApp(
    WidgetTester tester, {
    String route = '/today',
    FakeSettingsApi? settingsApi,
    FakeEntryApi? entryApi,
    FakeTimerApi? timerApi,
    bool settle = true,
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
        settingsApiBuilder: (_) => settingsApi ?? FakeSettingsApi(),
        entryApiBuilder: (_) => entryApi ?? FakeEntryApi(),
        timerApiBuilder: (_) => timerApi ?? FakeTimerApi(),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
    return AppStateScope.read(tester.element(find.byType(AppShell)));
  }

  group('themes and density', () {
    test('all four theme preferences build from the Deep Teal seed', () {
      expect(AppTheme.seed, const Color(0xFF00696D));

      final systemLight = AppTheme.build(
        ThemePreference.system,
        system: Brightness.light,
      );
      final systemDark = AppTheme.build(
        ThemePreference.system,
        system: Brightness.dark,
      );
      final light = AppTheme.build(ThemePreference.light);
      final dark = AppTheme.build(ThemePreference.dark);
      final highContrast = AppTheme.build(ThemePreference.highContrast);

      expect(systemLight.brightness, Brightness.light);
      expect(systemDark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
      expect(dark.brightness, Brightness.dark);
      expect(highContrast.brightness, Brightness.light);

      // Every scheme is seeded from the same Deep Teal source.
      expect(light.colorScheme.primary, systemLight.colorScheme.primary);
      expect(dark.colorScheme.primary, systemDark.colorScheme.primary);
      expect(
        highContrast.colorScheme.primary,
        isNot(light.colorScheme.primary),
        reason: 'High Contrast must strengthen the generated scheme',
      );
      expect(highContrast.colorScheme.onSurface, isNot(light.colorScheme.onSurface));
    });

    test('comfortable and compact densities change the shared theme', () {
      final comfortable = AppTheme.build(ThemePreference.light);
      final compact = AppTheme.build(
        ThemePreference.light,
        density: DensityPreference.compact,
      );

      expect(comfortable.visualDensity, VisualDensity.standard);
      expect(compact.visualDensity, VisualDensity.compact);
      expect(comfortable.listTileTheme.dense, isFalse);
      expect(compact.listTileTheme.dense, isTrue);
    });

    testWidgets('settings applies theme and density immediately', (tester) async {
      final settingsApi = FakeSettingsApi();
      await pumpApp(tester, route: '/settings', settingsApi: settingsApi);

      ThemeData currentTheme() => Theme.of(
        tester.element(find.byType(SettingsScreen)),
      );

      expect(currentTheme().brightness, Brightness.light);

      await tester.scrollUntilVisible(
        find.text('Appearance'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(currentTheme().brightness, Brightness.dark);
      expect(settingsApi.settings.theme, ThemePreference.dark);
      expect(find.text('Theme set to Dark'), findsOneWidget);

      // Let the first snackbar retire so the density confirmation is visible.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Compact'));
      await tester.pumpAndSettle();
      expect(currentTheme().visualDensity, VisualDensity.compact);
      expect(settingsApi.settings.density, DensityPreference.compact);
      expect(find.text('Density set to Compact'), findsOneWidget);

      await tester.tap(find.text('High contrast'));
      await tester.pumpAndSettle();
      expect(currentTheme().brightness, Brightness.light);
      expect(
        currentTheme().colorScheme.primary,
        AppTheme.build(ThemePreference.highContrast).colorScheme.primary,
      );
      expect(settingsApi.settings.theme, ThemePreference.highContrast);

      await tester.tap(find.text('System'));
      await tester.pumpAndSettle();
      expect(settingsApi.settings.theme, ThemePreference.system);
    });
  });

  group('keyboard shortcuts', () {
    testWidgets('T starts and stops the timer', (tester) async {
      final state = await pumpApp(tester);
      expect(state.activeTimer, isNull);
      state.lastCategoryId = 'cat-1';

      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.activeTimer, isNotNull);
    });

    testWidgets('N opens a new work entry', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
      await tester.pumpAndSettle();
      expect(find.text('New entry'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New entry'), findsNothing);
    });

    testWidgets('S opens the support entry form', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.pumpAndSettle();
      expect(find.text('Log support'), findsWidgets);

      await tester.tap(find.text('Cancel').first);
      await tester.pumpAndSettle();
    });

    testWidgets('G then T/L/I/C navigates between screens', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(find.text('Add entry'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyI);
      await tester.pumpAndSettle();
      expect(find.text('New project'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.pumpAndSettle();
      expect(find.text('Create check-in'), findsWidgets);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyG);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await tester.pumpAndSettle();
      expect(find.text('Start a timer'), findsOneWidget);
    });

    testWidgets('/ opens Log with the search field focused', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.slash, character: '/');
      await tester.pumpAndSettle();

      final search = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'Search entries…  /',
      );
      expect(search, findsOneWidget);
      expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
    });

    testWidgets('? opens the shortcut reference', (tester) async {
      await pumpApp(tester);

      await tester.sendKeyEvent(
        LogicalKeyboardKey.slash,
        character: '?',
        physicalKey: PhysicalKeyboardKey.slash,
      );
      await tester.pumpAndSettle();
      expect(find.text('Keyboard shortcuts'), findsOneWidget);
    });
  });

  group('focus rings and keyboard operation', () {
    test('theme focus treatment is strong enough to see', () {
      for (final preference in ThemePreference.values) {
        final theme = AppTheme.build(preference);
        expect(theme.focusColor.a, greaterThan(0.15));

        final focusedSide = theme.textButtonTheme.style?.side?.resolve({
          WidgetState.focused,
        });
        expect(focusedSide, isNotNull);
        expect(focusedSide!.width, AppTheme.focusRingWidth);
        expect(focusedSide.color, theme.colorScheme.primary);
      }
    });

    testWidgets('focus ring appears on keyboard focus and Enter activates', (
      tester,
    ) async {
      var activated = false;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(ThemePreference.light),
          home: Scaffold(
            body: Center(
              child: FocusRing(
                borderRadius: BorderRadius.circular(8),
                child: TextButton(
                  autofocus: true,
                  onPressed: () => activated = true,
                  child: const Text('Activate'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('focus-ring')), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(activated, isTrue);
    });

    testWidgets('navigation rail exposes a focus ring for every destination', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.build(ThemePreference.light),
          home: const Scaffold(
            body: SizedBox(width: 220, child: NavRail(currentPath: '/today')),
          ),
        ),
      );

      expect(find.byType(FocusRing), findsNWidgets(7));
    });
  });

  group('WCAG AA contrast', () {
    test('generated schemes meet AA for text and UI pairs', () {
      for (final preference in ThemePreference.values) {
        final scheme = AppTheme.build(preference).colorScheme;
        final textPairs = <String, List<Color>>{
          'onSurface on surface': [scheme.onSurface, scheme.surface],
          'onSurfaceVariant on surface': [
            scheme.onSurfaceVariant,
            scheme.surface,
          ],
          'onPrimary on primary': [scheme.onPrimary, scheme.primary],
          'onPrimaryContainer on primaryContainer': [
            scheme.onPrimaryContainer,
            scheme.primaryContainer,
          ],
          'onSecondaryContainer on secondaryContainer': [
            scheme.onSecondaryContainer,
            scheme.secondaryContainer,
          ],
          'onTertiaryContainer on tertiaryContainer': [
            scheme.onTertiaryContainer,
            scheme.tertiaryContainer,
          ],
          'onError on error': [scheme.onError, scheme.error],
          'onErrorContainer on errorContainer': [
            scheme.onErrorContainer,
            scheme.errorContainer,
          ],
          'onInverseSurface on inverseSurface': [
            scheme.onInverseSurface,
            scheme.inverseSurface,
          ],
        };
        for (final entry in textPairs.entries) {
          final ratio = _contrastRatio(entry.value[0], entry.value[1]);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason: '${preference.name}: ${entry.key} is $ratio',
          );
        }

        final uiPairs = <String, List<Color>>{
          'primary on surface': [scheme.primary, scheme.surface],
          'secondary on surface': [scheme.secondary, scheme.surface],
          'tertiary on surface': [scheme.tertiary, scheme.surface],
          'error on surface': [scheme.error, scheme.surface],
          'outline on surface': [scheme.outline, scheme.surface],
        };
        for (final entry in uiPairs.entries) {
          final ratio = _contrastRatio(entry.value[0], entry.value[1]);
          expect(
            ratio,
            greaterThanOrEqualTo(3),
            reason: '${preference.name}: ${entry.key} is $ratio',
          );
        }
      }
    });
  });

  group('timer state is conveyed without colour', () {
    testWidgets('running and paused states use icon and text cues', (
      tester,
    ) async {
      final entryApi = FakeEntryApi();
      final timerApi = FakeTimerApi();
      final state = AppState(
        categoryApi: FakeCategoryApi(
          categories: [_category('cat-1', 'Initiatives')],
        ),
        settingsApi: FakeSettingsApi(),
        entryApi: entryApi,
        timerApi: timerApi,
      );
      await tester.runAsync(() async {
        await state.load();
        await state.startTimer(categoryId: 'cat-1');
      });

      await tester.pumpWidget(
        AppStateScope(
          state: state,
          child: MaterialApp(
            theme: AppTheme.build(ThemePreference.light),
            home: const Scaffold(body: Center(child: TimerPill())),
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.timer_outlined), findsOneWidget);
      expect(find.text('Paused'), findsNothing);

      await state.pauseTimer();
      await tester.pump();

      expect(find.byIcon(Icons.pause_circle_outline), findsOneWidget);
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);

      // Stop the poll ticker before the test framework checks for pending
      // timers.
      state.dispose();
    });
  });

  group('tabular figures and ISO-like dates', () {
    test('dates and times use unambiguous, ISO-like order', () {
      final date = DateTime(2025, 10, 17, 9, 5);

      expect(isoDate(date), '2025-10-17');
      expect(formatTime(date), '09:05');
      expect(formatShortDate(date), '17 Oct');

      final full = formatFullDate(date);
      expect(full.endsWith('2025'), isTrue);
      expect(full.indexOf('17'), lessThan(full.indexOf('Oct')));

      expect(formatTimeRange(date, DateTime(2025, 10, 17, 9, 57)),
          '09:05–09:57');
    });

    testWidgets('compact density tightens data rows', (tester) async {
      final start = DateTime(2026, 10, 23, 9, 15);
      final entry = WorkEntry(
        id: 'entry-1',
        categoryId: 'cat-1',
        subcategoryId: 'sub-1',
        description: 'Backfill script skeleton',
        startedAt: start,
        endedAt: start.add(const Duration(minutes: 42)),
        minutes: 42,
        localDate: '2026-10-23',
        createdAt: start,
        updatedAt: start,
      );

      Future<double> workRowTopPadding(DensityPreference density) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.build(
              ThemePreference.light,
              density: density,
            ),
            home: Scaffold(
              body: WorkEntryRow(entry: entry, onEditOutcome: (_) {}),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(WorkEntryRow),
                matching: find.byType(Container),
              )
              .first,
        );
        return (container.padding! as EdgeInsets).top;
      }

      final comfortable = await workRowTopPadding(
        DensityPreference.comfortable,
      );
      final compact = await workRowTopPadding(DensityPreference.compact);

      expect(compact, lessThan(comfortable));
      expect(comfortable, 10);
      expect(compact, 6);
    });
  });

  group('quick capture regression', () {
    testWidgets('Enter still logs a one-line capture with the default duration', (
      tester,
    ) async {
      final entryApi = FakeEntryApi();
      final state = await pumpApp(
        tester,
        settingsApi: FakeSettingsApi(
          settings: const AppSettings(defaultDurationMinutes: 45),
        ),
        entryApi: entryApi,
      );

      expect(state.hasEntryService, isTrue);
      expect(find.byType(QuickCaptureBar), findsOneWidget);

      final description = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText == 'What did you do?',
      );
      await tester.enterText(description, 'Planned the sprint');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(entryApi.drafts, hasLength(1));
      expect(entryApi.drafts.single.description, 'Planned the sprint');
      expect(entryApi.drafts.single.minutes, 45);
      expect(find.textContaining('Logged 45m'), findsOneWidget);
    });
  });
}
