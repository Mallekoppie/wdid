import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/app.dart';
import 'package:wdid_web/data/demo_repository.dart';
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
        repository: DemoWdidRepository(latency: Duration.zero),
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
