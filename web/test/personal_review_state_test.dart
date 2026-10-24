import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/data/demo_repository.dart';
import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/models/check_in.dart';
import 'package:wdid_web/models/drafts.dart';
import 'package:wdid_web/models/enums.dart';
import 'package:wdid_web/state/app_state.dart';

import 'fake_checkin_api.dart';
import 'fake_preferences_api.dart';
import 'fake_summary_api.dart';

CheckIn finalManager() => CheckIn(
  id: 'manager-final',
  kind: CheckInKind.manager,
  state: CheckInState.final_,
  audience: CheckInAudience.oneOnOne,
  focusNotes: 'Manager focus',
  periodStart: DateTime(2026, 10, 1),
  periodEnd: DateTime(2026, 10, 10),
  createdAt: DateTime.utc(2026, 10, 10, 12),
  totals: const CheckInTotals(minutes: 240),
);

Future<(AppState, FakeCheckInApi, FakeSettingsApi)> buildState({
  ReviewCadence cadence = ReviewCadence.weekly,
  List<CheckIn>? checkIns,
}) async {
  final api = FakeCheckInApi(checkIns: checkIns ?? [finalManager()]);
  final settings = FakeSettingsApi(
    settings: AppSettings(reviewCadence: cadence),
  );
  final state = AppState(
    DemoWdidRepository(latency: Duration.zero),
    settingsApi: settings,
    summaryApi: FakeSummaryApi(echoDates: true),
    checkInApi: api,
  );
  await state.load();
  addTearDown(state.dispose);
  return (state, api, settings);
}

void main() {
  test('saving, editing and deleting a personal review never moves the boundary', () async {
    final (state, api, _) = await buildState();
    final boundary = state.defaultCheckInStart;
    expect(boundary, DateTime(2026, 10, 11));

    final personal = await state.createCheckIn(
      CheckInDraft(
        periodStart: DateTime(2026, 10, 4),
        periodEnd: DateTime(2026, 10, 10),
        kind: CheckInKind.personal,
        focusNotes: 'What moved?',
      ),
    );
    expect(personal.kind, CheckInKind.personal);
    expect(state.latestFinalManagerCheckIn?.id, 'manager-final');
    expect(state.defaultCheckInStart, boundary);

    await state.updateCheckIn(
      personal.copyWith(
        focusNotes: 'What moved, what did not',
        summaryMarkdown: '## Highlights',
      ),
    );
    expect(state.latestFinalManagerCheckIn?.id, 'manager-final');
    expect(state.defaultCheckInStart, boundary);

    await state.deleteCheckIn(personal.id);
    expect(state.checkIns.any((checkIn) => checkIn.id == personal.id), isFalse);
    expect(state.latestFinalManagerCheckIn?.id, 'manager-final');
    expect(state.defaultCheckInStart, boundary);
    expect(api.createRequests, hasLength(1));
    expect(api.deleteRequests, [personal.id]);
  });

  test('the weekly cadence offers a prompt until one is saved or dismissed', () async {
    final (state, api, _) = await buildState();

    expect(state.reviewPromptDue, isTrue);
    expect(state.reviewPromptPeriodKey, startsWith('week:'));
    expect(state.reviewPromptPeriod.timeframe.name, 'last7Days');
    // A prompt is only a hint: loading and deciding never creates a draft.
    expect(api.createRequests, isEmpty);

    state.dismissReviewPrompt();
    expect(state.reviewPromptDue, isFalse);
  });

  test('the monthly cadence uses a month key and a thirty-day prompt', () async {
    final (state, _, _) = await buildState(cadence: ReviewCadence.monthly);

    expect(state.reviewPromptDue, isTrue);
    expect(state.reviewPromptPeriodKey, startsWith('month:'));
    expect(state.reviewPromptPeriod.timeframe.name, 'last30Days');
  });

  test('off never prompts', () async {
    final (state, _, _) = await buildState(cadence: ReviewCadence.off);

    expect(state.reviewPromptDue, isFalse);
    expect(state.reviewPromptPeriodKey, isEmpty);
  });

  test('a saved personal review satisfies the current cadence period', () async {
    final (state, api, _) = await buildState();
    // The fake assigns creation times; pin it to the app's "today" so this
    // review belongs to the current week.
    api.now = DateTime.now();

    await state.createCheckIn(
      CheckInDraft(
        periodStart: DateTime.now().subtract(const Duration(days: 6)),
        periodEnd: DateTime.now(),
        kind: CheckInKind.personal,
      ),
    );

    expect(state.reviewPromptDue, isFalse);
  });
}
