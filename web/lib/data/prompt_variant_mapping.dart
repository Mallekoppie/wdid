import '../models/enums.dart';
import '../src/generated/check_ins.pbenum.dart' as generated;

/// Maps the UI prompt variant onto the wire enum. A null variant is the
/// unspecified value, which asks the service for its default.
generated.CheckInPromptVariant promptVariantToProto(
  CheckInPromptVariant? variant,
) => switch (variant) {
  CheckInPromptVariant.managerOneOnOne =>
    generated.CheckInPromptVariant.CHECK_IN_PROMPT_VARIANT_MANAGER_ONE_ON_ONE,
  CheckInPromptVariant.managerPerformanceReview =>
    generated
        .CheckInPromptVariant
        .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW,
  CheckInPromptVariant.personalReview =>
    generated.CheckInPromptVariant.CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW,
  null => generated.CheckInPromptVariant.CHECK_IN_PROMPT_VARIANT_UNSPECIFIED,
};

/// Maps the wire prompt variant onto the UI enum. An unspecified or unknown
/// value falls back to the manager 1:1 default.
CheckInPromptVariant promptVariantFromProto(
  generated.CheckInPromptVariant variant,
) => switch (variant) {
  generated
      .CheckInPromptVariant
      .CHECK_IN_PROMPT_VARIANT_MANAGER_PERFORMANCE_REVIEW =>
    CheckInPromptVariant.managerPerformanceReview,
  generated.CheckInPromptVariant.CHECK_IN_PROMPT_VARIANT_PERSONAL_REVIEW =>
    CheckInPromptVariant.personalReview,
  _ => CheckInPromptVariant.managerOneOnOne,
};
