import 'package:flutter_test/flutter_test.dart';

import 'package:wdid_web/models/app_settings.dart';
import 'package:wdid_web/utils/review_timeframe.dart';

void main() {
  final today = DateTime(2026, 10, 23); // a Friday
  final boundary = DateTime(2026, 10, 11);

  ReviewPeriod period(
    ReviewTimeframe timeframe, {
    int weekStart = 1,
    DateTime? customStart,
    DateTime? customEnd,
  }) {
    return reviewPeriodFor(
      timeframe,
      today: today,
      boundaryStart: boundary,
      weekStart: weekStart,
      customStart: customStart,
      customEnd: customEnd,
    );
  }

  test('every preset resolves to inclusive local dates', () {
    expect(period(ReviewTimeframe.last7Days).start, DateTime(2026, 10, 17));
    expect(period(ReviewTimeframe.last7Days).end, today);
    expect(period(ReviewTimeframe.last7Days).daysCovered, 7);

    expect(period(ReviewTimeframe.last30Days).start, DateTime(2026, 9, 24));
    expect(period(ReviewTimeframe.last30Days).daysCovered, 30);

    expect(period(ReviewTimeframe.thisWeek).start, DateTime(2026, 10, 19));
    expect(period(ReviewTimeframe.thisWeek).end, today);

    expect(period(ReviewTimeframe.thisMonth).start, DateTime(2026, 10, 1));
    expect(period(ReviewTimeframe.thisMonth).end, today);

    expect(
      period(ReviewTimeframe.sinceLastManagerCheckIn).start,
      boundary,
    );
    expect(period(ReviewTimeframe.sinceLastManagerCheckIn).end, today);
  });

  test('this week follows the configured week start', () {
    // Sunday-first week: Friday 23 Oct belongs to the week from 18 Oct.
    expect(
      period(ReviewTimeframe.thisWeek, weekStart: 7).start,
      DateTime(2026, 10, 18),
    );
  });

  test('a boundary after today is clamped instead of producing a future period', () {
    final resolved = reviewPeriodFor(
      ReviewTimeframe.sinceLastManagerCheckIn,
      today: today,
      boundaryStart: DateTime(2026, 10, 30),
    );
    expect(resolved.start, today);
    expect(resolved.end, today);
  });

  test('a custom range uses the picked dates', () {
    final custom = period(
      ReviewTimeframe.custom,
      customStart: DateTime(2026, 10, 2),
      customEnd: DateTime(2026, 10, 9),
    );
    expect(custom.start, DateTime(2026, 10, 2));
    expect(custom.end, DateTime(2026, 10, 9));
    expect(custom.daysCovered, 8);
    // Without dates it offers the same last-seven-days default as the dialog.
    expect(period(ReviewTimeframe.custom).start, DateTime(2026, 10, 17));
  });

  test('the cadence prompt reviews the last week or month', () {
    expect(
      reviewPromptPeriodFor(
        ReviewCadence.weekly,
        today: today,
        boundaryStart: boundary,
      ).timeframe,
      ReviewTimeframe.last7Days,
    );
    expect(
      reviewPromptPeriodFor(
        ReviewCadence.monthly,
        today: today,
        boundaryStart: boundary,
      ).timeframe,
      ReviewTimeframe.last30Days,
    );
  });

  test('validation rejects reversed and future ranges', () {
    expect(
      validateReviewPeriod(
        DateTime(2026, 10, 20),
        DateTime(2026, 10, 19),
        today: today,
      ),
      contains('on or before'),
    );
    expect(
      validateReviewPeriod(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 24),
        today: today,
      ),
      contains('future'),
    );
    expect(
      validateReviewPeriod(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 23),
        today: today,
      ),
      isNull,
    );
  });
}
