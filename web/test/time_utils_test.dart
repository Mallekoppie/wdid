import 'package:flutter_test/flutter_test.dart';
import 'package:wdid_web/utils/time_utils.dart';

void main() {
  group('formatDuration', () {
    test('renders minutes, hours, and mixed durations', () {
      expect(formatDuration(0), '0m');
      expect(formatDuration(42), '42m');
      expect(formatDuration(60), '1h');
      expect(formatDuration(375), '6h 15m');
    });
  });

  group('formatClock', () {
    test('renders zero-padded timer values', () {
      expect(formatClock(const Duration(seconds: 5)), '00:00:05');
      expect(
        formatClock(const Duration(hours: 2, minutes: 3, seconds: 4)),
        '02:03:04',
      );
    });
  });

  group('startOfWeek', () {
    test('honours a Monday week start', () {
      final wednesday = DateTime(2026, 10, 14);
      expect(startOfWeek(wednesday), DateTime(2026, 10, 12));
    });

    test('honours a Sunday week start', () {
      final wednesday = DateTime(2026, 10, 14);
      expect(startOfWeek(wednesday, weekStart: 7), DateTime(2026, 10, 11));
    });
  });
}
