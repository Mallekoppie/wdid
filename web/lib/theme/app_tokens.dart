import 'dart:ui';

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class AppRadius {
  static const double card = 12;
  static const double input = 8;
  static const double pill = 999;
}

abstract final class AppSizes {
  static const double navWidth = 208;
  static const double headerHeight = 64;
  static const double contentMaxWidth = 1180;
  static const double rowComfortable = 48;
  static const double rowCompact = 36;
}

/// Times and durations must always align vertically.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];
