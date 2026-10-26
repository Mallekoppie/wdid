import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/widgets/person_picker.dart';

import 'fake_preferences_api.dart';

typedef PickerHarness = ({AppState state, FakeSettingsApi api});

Future<PickerHarness> pumpPicker(
  WidgetTester tester, {
  List<String> selected = const [],
  ValueChanged<List<String>>? onChanged,
  ValueChanged<List<String>>? onCommitted,
  ValueChanged<List<String>>? onSubmitted,
  bool oneTap = false,
  bool compact = false,
  bool autofocus = false,
  String? errorText,
  List<String> roster = const ['Priya', 'Sam'],
}) async {
  final api = FakeSettingsApi(settings: AppSettings(supportPeople: roster));
  final state = AppState(settingsApi: api);
  await state.load();
  addTearDown(state.dispose);

  final selection = [...selected];
  await tester.pumpWidget(
    AppStateScope(
      state: state,
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setPickerState) => PersonPicker(
                selected: selection,
                compact: compact,
                autofocus: autofocus,
                errorText: errorText,
                oneTap: oneTap,
                onChanged: (people) {
                  setPickerState(() {
                    selection
                      ..clear()
                      ..addAll(people);
                  });
                  onChanged?.call(people);
                },
                onCommitted: onCommitted,
                onSubmitted: onSubmitted,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (state: state, api: api);
}

ChoiceChip chipFor(WidgetTester tester, String name) =>
    tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, name));

void main() {
  testWidgets('shows roster names as toggleable chips', (tester) async {
    await pumpPicker(tester);

    expect(find.widgetWithText(ChoiceChip, 'Priya'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sam'), findsOneWidget);
    expect(chipFor(tester, 'Priya').selected, isFalse);
  });

  testWidgets('tapping roster chips toggles membership in order', (
    tester,
  ) async {
    final changed = <List<String>>[];
    await pumpPicker(tester, onChanged: changed.add);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Priya'));
    await tester.pump();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Sam'));
    await tester.pump();

    expect(changed.last, ['Priya', 'Sam']);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Priya'));
    await tester.pump();

    expect(changed.last, ['Sam']);
  });

  testWidgets('a selected name renders as a checked roster chip', (
    tester,
  ) async {
    await pumpPicker(tester, selected: const ['Priya']);

    expect(chipFor(tester, 'Priya').selected, isTrue);
    expect(chipFor(tester, 'Sam').selected, isFalse);
  });

  testWidgets('typing a new name commits it once and grows the roster', (
    tester,
  ) async {
    final changed = <List<String>>[];
    final committed = <List<String>>[];
    final harness = await pumpPicker(
      tester,
      onChanged: changed.add,
      onCommitted: committed.add,
    );

    await tester.enterText(find.byType(TextFormField), '  Alex  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(changed.last, ['Alex']);
    expect(committed.single, ['Alex']);
    expect(harness.state.supportPeople, ['Priya', 'Sam', 'Alex']);
    expect(harness.api.settings.supportPeople, ['Priya', 'Sam', 'Alex']);
    expect(harness.api.updateCalls, 1);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      isEmpty,
    );
  });

  testWidgets(
    'adding an existing name is case-insensitive and keeps spelling',
    (tester) async {
      final changed = <List<String>>[];
      final harness = await pumpPicker(
        tester,
        selected: const ['Priya'],
        onChanged: changed.add,
      );

      await tester.enterText(find.byType(TextFormField), 'priya');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(changed, isEmpty);
      expect(harness.state.supportPeople, ['Priya', 'Sam']);
      expect(harness.api.updateCalls, 0);
    },
  );

  testWidgets('selected names can be removed with their delete action', (
    tester,
  ) async {
    final changed = <List<String>>[];
    await pumpPicker(
      tester,
      selected: const ['Priya', 'Alex'],
      onChanged: changed.add,
    );

    // Alex is not on the roster, so it is shown as a removable chip.
    expect(find.widgetWithText(InputChip, 'Alex'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove Alex'));
    await tester.pump();

    expect(changed.last, ['Priya']);
  });

  testWidgets('typing filters the roster chips', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextFormField), 'pr');
    await tester.pump();

    expect(find.widgetWithText(ChoiceChip, 'Priya'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sam'), findsNothing);
  });

  testWidgets('one-tap mode commits a chip as a single-name batch', (
    tester,
  ) async {
    final changed = <List<String>>[];
    final committed = <List<String>>[];
    await pumpPicker(
      tester,
      oneTap: true,
      onChanged: changed.add,
      onCommitted: committed.add,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Priya'));
    await tester.pump();

    expect(committed.single, ['Priya']);
    expect(changed.single, ['Priya']);
  });

  testWidgets('shows an external error and supports compact chips', (
    tester,
  ) async {
    await pumpPicker(tester, compact: true, errorText: 'Who did you support?');

    expect(find.text('Who did you support?'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Priya'), findsOneWidget);
  });

  testWidgets('an empty roster still offers a free-text field', (tester) async {
    final harness = await pumpPicker(tester, roster: const []);

    expect(find.byType(ChoiceChip), findsNothing);
    expect(find.byType(TextFormField), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'Alex');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(harness.state.supportPeople, ['Alex']);
  });

  testWidgets('the add action commits a typed name', (tester) async {
    final harness = await pumpPicker(tester);

    await tester.enterText(find.byType(TextFormField), 'Alex');
    await tester.tap(find.byTooltip('Add person'));
    await tester.pump();

    expect(harness.state.supportPeople, ['Priya', 'Sam', 'Alex']);
  });

  testWidgets('the add action commits without submitting', (tester) async {
    final committed = <List<String>>[];
    final submitted = <List<String>>[];
    await pumpPicker(
      tester,
      onCommitted: committed.add,
      onSubmitted: submitted.add,
    );

    await tester.enterText(find.byType(TextFormField), 'Alex');
    await tester.tap(find.byTooltip('Add person'));
    await tester.pump();

    expect(committed.single, ['Alex']);
    expect(
      submitted,
      isEmpty,
      reason: 'the add action must not save or start a timer',
    );
  });

  testWidgets('the add action commits without submitting in one-tap mode', (
    tester,
  ) async {
    final committed = <List<String>>[];
    final submitted = <List<String>>[];
    await pumpPicker(
      tester,
      oneTap: true,
      onCommitted: committed.add,
      onSubmitted: submitted.add,
    );

    await tester.enterText(find.byType(TextFormField), 'Alex');
    await tester.tap(find.byTooltip('Add person'));
    await tester.pump();

    expect(committed.single, ['Alex']);
    expect(
      submitted,
      isEmpty,
      reason: 'the add action must not start support in one-tap mode',
    );
  });

  testWidgets('Enter commits and submits a typed name', (tester) async {
    final committed = <List<String>>[];
    final submitted = <List<String>>[];
    await pumpPicker(
      tester,
      onCommitted: committed.add,
      onSubmitted: submitted.add,
    );

    await tester.enterText(find.byType(TextFormField), 'Alex');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(committed.single, ['Alex']);
    expect(submitted.single, ['Alex']);
  });

  testWidgets('autofocus focuses the new-name field', (tester) async {
    await pumpPicker(tester, autofocus: true);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });

  testWidgets('the shared dialog keeps typed text that was never committed', (
    tester,
  ) async {
    final api = FakeSettingsApi(
      settings: const AppSettings(supportPeople: ['Priya']),
    );
    final state = AppState(settingsApi: api);
    await state.load();
    addTearDown(state.dispose);

    List<String>? picked;
    await tester.pumpWidget(
      AppStateScope(
        state: state,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  picked = await showPeoplePickerDialog(context);
                },
                child: const Text('Open picker'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open picker'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  Alex ');
    await tester.pump();

    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Start support'),
    );
    expect(start.onPressed, isNotNull, reason: 'typed text counts');

    await tester.tap(find.widgetWithText(FilledButton, 'Start support'));
    await tester.pumpAndSettle();

    expect(picked, ['Alex']);
    expect(state.supportPeople, ['Priya', 'Alex']);
  });
}
