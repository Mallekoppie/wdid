import 'package:intl/intl.dart';

final DateFormat _dayHeader = DateFormat('EEE d MMM');
final DateFormat _fullDate = DateFormat('EEE d MMM yyyy');
final DateFormat _shortDate = DateFormat('d MMM');
final DateFormat _monthYear = DateFormat('MMM yyyy');
final DateFormat _clock = DateFormat('HH:mm');
final DateFormat _iso = DateFormat('yyyy-MM-dd');

DateTime dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String isoDate(DateTime value) => _iso.format(value);

String formatTime(DateTime value) => _clock.format(value.toLocal());

String formatDayHeader(DateTime value) => _dayHeader.format(value);

String formatFullDate(DateTime value) => _fullDate.format(value);

String formatShortDate(DateTime value) => _shortDate.format(value);

String formatMonthYear(DateTime value) => _monthYear.format(value);

String formatRange(DateTime start, DateTime end) {
  if (start.year == end.year) {
    return '${_shortDate.format(start)} → ${_shortDate.format(end)} ${end.year}';
  }
  return '${_shortDate.format(start)} ${start.year} → '
      '${_shortDate.format(end)} ${end.year}';
}

/// Compact human duration, e.g. `42m`, `6h`, `6h 15m`.
String formatDuration(int minutes) {
  final safe = minutes < 0 ? 0 : minutes;
  final hours = safe ~/ 60;
  final remainder = safe % 60;
  if (hours == 0) return '${remainder}m';
  if (remainder == 0) return '${hours}h';
  return '${hours}h ${remainder}m';
}

/// Timer display, e.g. `00:42:13`.
String formatClock(Duration duration) {
  final safe = duration.isNegative ? Duration.zero : duration;
  final hours = safe.inHours.toString().padLeft(2, '0');
  final minutes = (safe.inMinutes % 60).toString().padLeft(2, '0');
  final seconds = (safe.inSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String formatTimeRange(DateTime start, DateTime end) =>
    '${formatTime(start)}–${formatTime(end)}';

int minutesBetween(DateTime start, DateTime end) =>
    end.difference(start).inMinutes;

DateTime startOfWeek(DateTime value, {int weekStart = 1}) {
  final day = dateOnly(value);
  final offset = (day.weekday - weekStart) % 7;
  return day.subtract(Duration(days: offset));
}

DateTime startOfQuarter(DateTime value) {
  final month = ((value.month - 1) ~/ 3) * 3 + 1;
  return DateTime(value.year, month, 1);
}

DateTime addDays(DateTime value, int days) =>
    dateOnly(value).add(Duration(days: days));

DateTime addMonths(DateTime value, int months) =>
    DateTime(value.year, value.month + months, value.day);

int daysBetweenInclusive(DateTime start, DateTime end) =>
    dateOnly(end).difference(dateOnly(start)).inDays + 1;

/// `today`, `yesterday`, `3d ago`, then an ISO-like short date.
String formatRelativeDay(DateTime value, {DateTime? now}) {
  final today = dateOnly(now ?? DateTime.now());
  final target = dateOnly(value);
  final diff = today.difference(target).inDays;
  if (diff == 0) return 'today';
  if (diff == 1) return 'yesterday';
  if (diff > 1 && diff < 7) return '${diff}d ago';
  if (diff < 0) return _shortDate.format(target);
  return _shortDate.format(target);
}

String formatWeekdayShort(DateTime value) => DateFormat('EEE').format(value);

String formatBytes(int bytes) {
  if (bytes <= 0) return '—';
  const units = ['B', 'KB', 'MB', 'GB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}
