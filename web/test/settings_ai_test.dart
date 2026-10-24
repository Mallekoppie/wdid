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
  }) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final settings = FakeSettingsApi();
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

  testWidgets('AI settings save the base URL, model and redaction only', (
    tester,
  ) async {
    final settings = await pumpSettings(tester);

    expect(find.textContaining('WDID_OPENAI_API_KEY'), findsOneWidget);
    expect(find.text('Stored setting'), findsNothing);
    expect(
      find.textContaining('never stored, exported or logged'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextField, 'Base URL'),
      'https://provider.example/v1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Model'),
      'provider-model',
    );
    await tester.tap(find.byType(SwitchListTile));
    await tester.tap(find.widgetWithText(FilledButton, 'Save AI settings'));
    await tester.pumpAndSettle();

    expect(settings.updateCalls, 1);
    expect(settings.settings.aiBaseUrl, 'https://provider.example/v1');
    expect(settings.settings.aiModel, 'provider-model');
    expect(settings.settings.redactUrls, isTrue);
  });

  testWidgets('a delayed preferences load is not overwritten by editors', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final gate = Completer<void>();
    final settingsApi = FakeSettingsApi(
      settings: const AppSettings(
        timezone: 'Europe/Amsterdam',
        weekStart: 1,
        dailyTargetHours: 6.5,
        longTimerMinutes: 180,
        defaultDurationMinutes: 45,
        aiBaseUrl: 'https://stored.example/v1',
        aiModel: 'stored-model',
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

    String fieldText(String label) => tester
        .widget<TextField>(
          find.byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == label,
          ),
        )
        .controller!
        .text;

    expect(fieldText('Timezone'), 'Europe/Amsterdam');
    expect(fieldText('Daily target'), '6.5');
    expect(fieldText('Long timer prompt'), '180');
    expect(fieldText('Default duration'), '45');

    await tester.tap(find.widgetWithText(FilledButton, 'Save time settings'));
    await tester.pumpAndSettle();

    expect(settingsApi.updateCalls, 1);
    expect(settingsApi.settings.timezone, 'Europe/Amsterdam');
    expect(settingsApi.settings.dailyTargetHours, 6.5);
    expect(settingsApi.settings.longTimerMinutes, 180);
    expect(settingsApi.settings.defaultDurationMinutes, 45);

    await tester.tap(find.widgetWithText(FilledButton, 'Save AI settings'));
    await tester.pumpAndSettle();

    expect(settingsApi.updateCalls, 2);
    expect(settingsApi.settings.aiBaseUrl, 'https://stored.example/v1');
    expect(settingsApi.settings.aiModel, 'stored-model');
    expect(settingsApi.settings.redactUrls, isTrue);
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
