import '../models/app_settings.dart';
import 'time_utils.dart';

/// The timeframes a personal review can cover. They match the presets offered
/// by the Log so a user does not have to learn two vocabularies.
enum ReviewTimeframe {
  last7Days,
  last30Days,
  thisWeek,
  thisMonth,
  sinceLastManagerCheckIn,
  custom;

  String get label => switch (this) {
    ReviewTimeframe.last7Days => 'Last 7 days',
    ReviewTimeframe.last30Days => 'Last 30 days',
    ReviewTimeframe.thisWeek => 'This week',
    ReviewTimeframe.thisMonth => 'This month',
    ReviewTimeframe.sinceLastManagerCheckIn => 'Since last manager check-in',
    ReviewTimeframe.custom => 'Custom range',
  };
}

/// An inclusive local calendar range chosen for a live review.
class ReviewPeriod {
  const ReviewPeriod({
    required this.start,
    required this.end,
    required this.timeframe,
  });

  final DateTime start;
  final DateTime end;
  final ReviewTimeframe timeframe;

  int get daysCovered => daysBetweenInclusive(start, end);

  ReviewPeriod copyWith({
    DateTime? start,
    DateTime? end,
    ReviewTimeframe? timeframe,
  }) => ReviewPeriod(
    start: start ?? this.start,
    end: end ?? this.end,
    timeframe: timeframe ?? this.timeframe,
  );
}

/// Resolves a preset into inclusive dates. [today] is the user's local day and
/// [boundaryStart] is the day after the last final manager check-in, or the
/// journal start, or today. A boundary already past today is clamped so the
/// form always describes a real period.
ReviewPeriod reviewPeriodFor(
  ReviewTimeframe timeframe, {
  required DateTime today,
  required DateTime boundaryStart,
  int weekStart = 1,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final day = dateOnly(today);
  switch (timeframe) {
    case ReviewTimeframe.last7Days:
      return ReviewPeriod(
        start: addDays(day, -6),
        end: day,
        timeframe: timeframe,
      );
    case ReviewTimeframe.last30Days:
      return ReviewPeriod(
        start: addDays(day, -29),
        end: day,
        timeframe: timeframe,
      );
    case ReviewTimeframe.thisWeek:
      return ReviewPeriod(
        start: startOfWeek(day, weekStart: weekStart),
        end: day,
        timeframe: timeframe,
      );
    case ReviewTimeframe.thisMonth:
      return ReviewPeriod(
        start: DateTime(day.year, day.month, 1),
        end: day,
        timeframe: timeframe,
      );
    case ReviewTimeframe.sinceLastManagerCheckIn:
      final boundary = dateOnly(boundaryStart);
      return ReviewPeriod(
        start: boundary.isAfter(day) ? day : boundary,
        end: day,
        timeframe: timeframe,
      );
    case ReviewTimeframe.custom:
      final start = dateOnly(customStart ?? addDays(day, -6));
      final end = dateOnly(customEnd ?? day);
      return ReviewPeriod(start: start, end: end, timeframe: timeframe);
  }
}

/// The period the cadence prompt opens. A weekly prompt reviews the last seven
/// days and a monthly prompt the last thirty; neither creates a draft.
ReviewPeriod reviewPromptPeriodFor(
  ReviewCadence cadence, {
  required DateTime today,
  required DateTime boundaryStart,
  int weekStart = 1,
}) {
  final timeframe = cadence == ReviewCadence.monthly
      ? ReviewTimeframe.last30Days
      : ReviewTimeframe.last7Days;
  return reviewPeriodFor(
    timeframe,
    today: today,
    boundaryStart: boundaryStart,
    weekStart: weekStart,
  );
}

/// Validates a custom or edited range. An empty message means the range can be
/// saved; the service applies the same inclusive-date rule.
String? validateReviewPeriod(
  DateTime start,
  DateTime end, {
  required DateTime today,
}) {
  if (dateOnly(start).isAfter(dateOnly(end))) {
    return 'The start date must be on or before the end date.';
  }
  if (dateOnly(end).isAfter(dateOnly(today))) {
    return 'The end date cannot be in the future.';
  }
  return null;
}
