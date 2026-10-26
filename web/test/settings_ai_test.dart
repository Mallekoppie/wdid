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

  testWidgets('the prompt preview comes from the service template', (
    tester,
  ) async {
    final summaryApi = FakeSummaryApi()
      ..template = const PromptTemplate(
        template: 'SERVICE OWNED ONE ON ONE TEMPLATE',
        variant: CheckInPromptVariant.managerOneOnOne,
      );
    await pumpSettings(tester, summaryApi: summaryApi);

    await tester.tap(find.text('Prompt template preview'));
    await tester.pumpAndSettle();

    expect(
      summaryApi.lastTemplateVariant,
      CheckInPromptVariant.managerOneOnOne,
    );
    expect(find.text('SERVICE OWNED ONE ON ONE TEMPLATE'), findsOneWidget);
    expect(find.textContaining('Version v1 · service-owned'), findsOneWidget);
  });
}
