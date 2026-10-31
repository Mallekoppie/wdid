import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/enums.dart';

import 'fake_auth_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

void main() {
  Future<FakeSettingsApi> pumpSettings(
    WidgetTester tester, {
    FakeSummaryApi? summaryApi,
    FakeSettingsApi? settingsApi,
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = settingsApi ?? FakeSettingsApi();
    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
        settingsApiBuilder: (_) => settings,
        summaryApiBuilder: (_) => summaryApi ?? FakeSummaryApi(),
      ),
    );
    await tester.pumpAndSettle();
    return settings;
  }

  String fieldText(WidgetTester tester, String label) => tester
      .widget<TextField>(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField && widget.decoration?.labelText == label,
        ),
      )
      .controller!
      .text;

  testWidgets('AI settings save the preset, base URL, model and redaction', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);

    expect(find.text('No API key stored'), findsOneWidget);
    expect(find.textContaining('never returned'), findsOneWidget);
    expect(find.textContaining('WDID_OPENAI_API_KEY'), findsNothing);

    // Choosing a preset fills the endpoint and a starting model.
    await tester.tap(find.byType(DropdownButton<AIProviderPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'Base URL'), AIProviderPreset.deepSeek.baseUrl);
    expect(fieldText(tester, 'Model'), AIProviderPreset.deepSeek.model);

    // The model is always editable.
    await tester.enterText(
      find.widgetWithText(TextField, 'Model'),
      'custom-model',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save AI settings'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save AI settings'));
    await tester.pumpAndSettle();

    expect(settings.updateCalls, 1);
    expect(settings.settings.aiBaseUrl, AIProviderPreset.deepSeek.baseUrl);
    expect(settings.settings.aiModel, 'custom-model');
    expect(settings.settings.redactUrls, isTrue);
  });

  testWidgets('saving the key also persists a pending provider change', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);

    await tester.tap(find.byType(DropdownButton<AIProviderPreset>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DeepSeek').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'API key'),
      'sk-deepseek-user-key',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save key'));
    await tester.pumpAndSettle();

    // A key saved against the old endpoint authenticates against the wrong
    // provider, so the pending preset must land in the same action.
    expect(settings.updateCalls, 1);
    expect(settings.settings.aiBaseUrl, AIProviderPreset.deepSeek.baseUrl);
    expect(settings.settings.aiModel, AIProviderPreset.deepSeek.model);
    expect(settings.setKeyCalls, 1);
    expect(settings.lastApiKey, 'sk-deepseek-user-key');
  });

  testWidgets('saving AI settings also stores a typed key', (tester) async {
    final settings = await pumpSettings(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'API key'),
      'sk-ant-user-key',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save AI settings'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save AI settings'));
    await tester.pumpAndSettle();

    expect(settings.setKeyCalls, 1);
    expect(settings.lastApiKey, 'sk-ant-user-key');
    expect(settings.settings.hasAiApiKey, isTrue);
    expect(fieldText(tester, 'API key'), isEmpty);
  });

  testWidgets(
    'the API key is write-only and can be set, replaced and cleared',
    (tester) async {
      final settings = await pumpSettings(tester);

      expect(settings.settings.hasAiApiKey, isFalse);
      expect(find.text('No API key stored'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Clear key'), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'API key'),
        '  sk-ant-user-key  ',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Save key'));
      await tester.pumpAndSettle();

      expect(settings.setKeyCalls, 1);
      expect(settings.lastApiKey, 'sk-ant-user-key');
      expect(settings.settings.hasAiApiKey, isTrue);
      expect(find.text('API key stored'), findsOneWidget);
      // The editor never holds the stored key after saving.
      expect(fieldText(tester, 'API key'), isEmpty);
      expect(find.widgetWithText(TextButton, 'Clear key'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Clear key'));
      await tester.pumpAndSettle();

      expect(settings.clearKeyCalls, 1);
      expect(settings.settings.hasAiApiKey, isFalse);
      expect(find.text('No API key stored'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Clear key'), findsNothing);
    },
  );

  testWidgets('a delayed preferences load is not overwritten by editors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gate = Completer<void>();
    final settingsApi = FakeSettingsApi(
      settings: AppSettings(
        timezone: 'Europe/Amsterdam',
        weekStart: 1,
        dailyTargetHours: 6.5,
        longTimerMinutes: 180,
        defaultDurationMinutes: 45,
        aiBaseUrl: AIProviderPreset.deepSeek.baseUrl,
        aiModel: 'stored-model',
        hasAiApiKey: true,
        redactUrls: true,
      ),
    )..gate = gate;

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
        settingsApiBuilder: (_) => settingsApi,
        summaryApiBuilder: (_) => FakeSummaryApi(),
      ),
    );
    // The Settings route is built while GetSettings is still in flight, so
    // the editors initially hold the local defaults.
    await tester.pump();

    gate.complete();
    await tester.pumpAndSettle();

    expect(fieldText(tester, 'Timezone'), 'Europe/Amsterdam');
    expect(fieldText(tester, 'Daily target'), '6.5');
    expect(fieldText(tester, 'Long timer prompt'), '180');
    expect(fieldText(tester, 'Default duration'), '45');
    expect(fieldText(tester, 'Base URL'), AIProviderPreset.deepSeek.baseUrl);
    expect(fieldText(tester, 'Model'), 'stored-model');
    expect(find.text('API key stored'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Save time settings'));
    await tester.pumpAndSettle();

    expect(settingsApi.updateCalls, 1);
    expect(settingsApi.settings.timezone, 'Europe/Amsterdam');
    expect(settingsApi.settings.dailyTargetHours, 6.5);
    expect(settingsApi.settings.longTimerMinutes, 180);
    expect(settingsApi.settings.defaultDurationMinutes, 45);

    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save AI settings'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save AI settings'));
    await tester.pumpAndSettle();

    expect(settingsApi.updateCalls, 2);
    expect(settingsApi.settings.aiBaseUrl, AIProviderPreset.deepSeek.baseUrl);
    expect(settingsApi.settings.aiModel, 'stored-model');
    expect(settingsApi.settings.redactUrls, isTrue);
    expect(settingsApi.settings.hasAiApiKey, isTrue);
  });

  const rules = 'Use only the supplied data. Invent nothing.';

  PromptTemplate promptTemplate(
    CheckInPromptVariant variant,
    String body, {
    bool customised = false,
  }) => PromptTemplate(
    body: body,
    customised: customised,
    rules: rules,
    variant: variant,
  );

  FakeSettingsApi promptSettings({
    String oneOnOne = 'ONE ON ONE BODY',
    String performance = 'PERFORMANCE BODY',
    String personal = 'PERSONAL BODY',
    bool oneOnOneCustomised = false,
  }) => FakeSettingsApi(
    promptTemplates: {
      CheckInPromptVariant.managerOneOnOne: promptTemplate(
        CheckInPromptVariant.managerOneOnOne,
        oneOnOne,
        customised: oneOnOneCustomised,
      ),
      CheckInPromptVariant.managerPerformanceReview: promptTemplate(
        CheckInPromptVariant.managerPerformanceReview,
        performance,
      ),
      CheckInPromptVariant.personalReview: promptTemplate(
        CheckInPromptVariant.personalReview,
        personal,
      ),
    },
  );

  Future<void> openPromptEditor(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Prompt template'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Prompt template'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseVariant(
    WidgetTester tester,
    CheckInPromptVariant variant,
  ) async {
    final dropdown = find.byType(DropdownButton<CheckInPromptVariant>);
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    final label = switch (variant) {
      CheckInPromptVariant.managerOneOnOne => 'Manager 1:1',
      CheckInPromptVariant.managerPerformanceReview =>
        'Manager performance review',
      CheckInPromptVariant.personalReview => 'Personal review',
    };
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  String promptBody(WidgetTester tester) => fieldText(tester, 'Prompt body');

  testWidgets('the prompt editor loads every variant with the locked rules', (
    tester,
  ) async {
    final settings = await pumpSettings(tester, settingsApi: promptSettings());
    await openPromptEditor(tester);

    expect(settings.listPromptTemplatesCalls, 1);
    expect(promptBody(tester), 'ONE ON ONE BODY');
    expect(find.text('Locked rules'), findsOneWidget);
    expect(find.text(rules), findsOneWidget);
    expect(find.text('ONE ON ONE BODY\n\n$rules'), findsOneWidget);

    await chooseVariant(
      tester,
      CheckInPromptVariant.managerPerformanceReview,
    );
    expect(promptBody(tester), 'PERFORMANCE BODY');

    await chooseVariant(tester, CheckInPromptVariant.personalReview);
    expect(promptBody(tester), 'PERSONAL BODY');
  });

  testWidgets('saving one variant customises only that variant', (
    tester,
  ) async {
    final settings = await pumpSettings(tester, settingsApi: promptSettings());
    await openPromptEditor(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Prompt body'),
      '  MY CUSTOM ONE ON ONE  ',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save prompt'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save prompt'));
    await tester.pumpAndSettle();

    expect(settings.updatePromptTemplateCalls, 1);
    expect(
      settings.lastPromptTemplateVariant,
      CheckInPromptVariant.managerOneOnOne,
    );
    expect(settings.lastPromptTemplateBody, 'MY CUSTOM ONE ON ONE');
    expect(
      settings.promptTemplates[CheckInPromptVariant.managerPerformanceReview]!
          .body,
      'PERFORMANCE BODY',
    );
    expect(
      settings.promptTemplates[CheckInPromptVariant.personalReview]!.body,
      'PERSONAL BODY',
    );
    expect(find.text('Customised'), findsOneWidget);
    expect(find.text('MY CUSTOM ONE ON ONE\n\n$rules'), findsOneWidget);

    await chooseVariant(
      tester,
      CheckInPromptVariant.managerPerformanceReview,
    );
    expect(promptBody(tester), 'PERFORMANCE BODY');
  });

  testWidgets('reset restores the built-in body and clears the badge', (
    tester,
  ) async {
    final settings = await pumpSettings(
      tester,
      settingsApi: promptSettings(
        oneOnOne: 'MY CUSTOM ONE ON ONE',
        oneOnOneCustomised: true,
      ),
    );
    await openPromptEditor(tester);

    expect(find.text('Customised'), findsOneWidget);

    await tester.ensureVisible(
      find.widgetWithText(TextButton, 'Reset to default'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Reset to default'));
    await tester.pumpAndSettle();

    expect(settings.resetPromptTemplateCalls, 1);
    expect(
      settings.lastResetPromptTemplateVariant,
      CheckInPromptVariant.managerOneOnOne,
    );
    expect(
      promptBody(tester),
      'Built-in manager_one_on_one body.',
    );
    expect(find.text('Customised'), findsNothing);
  });

  testWidgets('a blank body is rejected before the service is called', (
    tester,
  ) async {
    final settings = await pumpSettings(tester, settingsApi: promptSettings());
    await openPromptEditor(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Prompt body'),
      '   ',
    );
    await tester.ensureVisible(
      find.widgetWithText(FilledButton, 'Save prompt'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save prompt'));
    await tester.pumpAndSettle();

    expect(settings.updatePromptTemplateCalls, 0);
    expect(find.textContaining('Enter a prompt body'), findsOneWidget);
  });

  testWidgets('a delayed template load cannot overwrite an in-progress edit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gate = Completer<void>();
    final settings = promptSettings()
      ..promptTemplatesGate = gate;

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
        settingsApiBuilder: (_) => settings,
        summaryApiBuilder: (_) => FakeSummaryApi(),
      ),
    );
    await tester.pump();

    // The service has not answered yet, but the editor is already usable. The
    // loading bar animates forever, so settle with fixed pumps instead.
    await tester.ensureVisible(find.text('Prompt template'));
    await tester.pump();
    await tester.tap(find.text('Prompt template'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(
      find.widgetWithText(TextField, 'Prompt body'),
      'DRAFT WHILE LOADING',
    );

    gate.complete();
    await tester.pumpAndSettle();

    expect(promptBody(tester), 'DRAFT WHILE LOADING');
    // The other variants still received the delayed load.
    await chooseVariant(tester, CheckInPromptVariant.personalReview);
    expect(promptBody(tester), 'PERSONAL BODY');
  });

  testWidgets('drafts are isolated per variant', (tester) async {
    await pumpSettings(tester, settingsApi: promptSettings());
    await openPromptEditor(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Prompt body'),
      'ONE ON ONE DRAFT',
    );

    await chooseVariant(
      tester,
      CheckInPromptVariant.managerPerformanceReview,
    );
    expect(promptBody(tester), 'PERFORMANCE BODY');
    await tester.enterText(
      find.widgetWithText(TextField, 'Prompt body'),
      'PERFORMANCE DRAFT',
    );

    await chooseVariant(tester, CheckInPromptVariant.managerOneOnOne);
    expect(promptBody(tester), 'ONE ON ONE DRAFT');

    await chooseVariant(tester, CheckInPromptVariant.personalReview);
    expect(promptBody(tester), 'PERSONAL BODY');
  });

  testWidgets('without the settings service the prompt stays a read-only preview', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final summaryApi = FakeSummaryApi()
      ..template = const PromptTemplate(
        template: 'READ ONLY SERVICE TEMPLATE',
        variant: CheckInPromptVariant.managerOneOnOne,
      );
    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
        summaryApiBuilder: (_) => summaryApi,
      ),
    );
    await tester.pumpAndSettle();

    await openPromptEditor(tester);

    expect(
      summaryApi.lastTemplateVariant,
      CheckInPromptVariant.managerOneOnOne,
    );
    expect(find.text('READ ONLY SERVICE TEMPLATE'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save prompt'), findsNothing);
  });

  testWidgets('without any prompt service the section explains what is missing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      WdidApp(
        authApi: FakeAuthApi(),
        initialSession: signedInSession(),
        initialRoute: '/settings',
      ),
    );
    await tester.pumpAndSettle();

    await openPromptEditor(tester);

    expect(find.textContaining('Connect the service'), findsOneWidget);
  });
}
