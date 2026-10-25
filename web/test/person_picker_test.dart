import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/state/app_state.dart';
import 'package:wdid_web/state/app_state_scope.dart';
import 'package:wdid_web/widgets/person_picker.dart';

import 'fake_preferences_api.dart';

typedef PickerHarness = ({
  AppState state,
  FakeSettingsApi api,
  TextEditingController controller,
});

Future<PickerHarness> pumpPicker(
  WidgetTester tester, {
  String initialText = '',
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSelected,
  ValueChanged<String>? onSubmitted,
  bool compact = false,
  bool autofocus = false,
  String? errorText,
  List<String> roster = const ['Priya', 'Sam'],
}) async {
  final api = FakeSettingsApi(settings: AppSettings(supportPeople: roster));
  final state = AppState(settingsApi: api);
  await state.load();
  addTearDown(state.dispose);

  final controller = TextEditingController(text: initialText);
  addTearDown(controller.dispose);

  await tester.pumpWidget(
    AppStateScope(
      state: state,
      child: MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: PersonPicker(
              controller: controller,
              compact: compact,
              autofocus: autofocus,
              errorText: errorText,
              onChanged: onChanged,
              onSelected: onSelected,
              onSubmitted: onSubmitted,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (state: state, api: api, controller: controller);
}

void main() {
  testWidgets('shows roster names as one-tap chips', (tester) async {
    await pumpPicker(tester);

    expect(find.widgetWithText(ChoiceChip, 'Priya'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sam'), findsOneWidget);
  });

  testWidgets('typing filters the roster chips', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'pr');
    await tester.pump();

    expect(find.widgetWithText(ChoiceChip, 'Priya'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Sam'), findsNothing);
  });

  testWidgets('tapping a chip fills the controller and selects the name', (
    tester,
  ) async {
    final changed = <String>[];
    final selected = <String>[];
    final submitted = <String>[];
    final harness = await pumpPicker(
      tester,
      onChanged: changed.add,
      onSelected: selected.add,
      onSubmitted: submitted.add,
    );

    await tester.tap(find.widgetWithText(ChoiceChip, 'Priya'));
    await tester.pump();

    expect(harness.controller.text, 'Priya');
    expect(selected, ['Priya']);
    expect(changed, ['Priya']);
    expect(submitted, isEmpty);
  });

  testWidgets('submitting a new name adds it to the roster', (tester) async {
    final selected = <String>[];
    final submitted = <String>[];
    final harness = await pumpPicker(
      tester,
      onSelected: selected.add,
      onSubmitted: submitted.add,
    );

    await tester.enterText(find.byType(TextField), '  Alex  ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(harness.controller.text, 'Alex');
    expect(harness.state.supportPeople, ['Priya', 'Sam', 'Alex']);
    expect(harness.api.settings.supportPeople, ['Priya', 'Sam', 'Alex']);
    expect(selected, ['Alex']);
    expect(submitted, ['Alex']);
  });

  testWidgets('the add action commits a typed name', (tester) async {
    final harness = await pumpPicker(tester);

    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.tap(find.byTooltip('Add person'));
    await tester.pump();

    expect(harness.state.supportPeople, ['Priya', 'Sam', 'Alex']);
  });

  testWidgets('committing an existing name is case-insensitive', (
    tester,
  ) async {
    final selected = <String>[];
    final harness = await pumpPicker(tester, onSelected: selected.add);

    await tester.enterText(find.byType(TextField), 'priya');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(harness.state.supportPeople, ['Priya', 'Sam']);
    expect(harness.api.updateCalls, 0);
    expect(selected, ['priya']);
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
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Alex');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(harness.state.supportPeople, ['Alex']);
  });

  testWidgets('autofocus focuses the new-name field', (tester) async {
    await pumpPicker(tester, autofocus: true);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);
  });
}
