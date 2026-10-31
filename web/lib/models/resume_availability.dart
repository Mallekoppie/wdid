/// Whether a work entry can be resumed into a new timer, and, when it cannot,
/// the short explanation shown in the action's tooltip.
///
/// The server accepts a start under an archived category, so the client owns
/// this gate. Today's row action and the Log's Resume menu item share it.
class ResumeAvailability {
  const ResumeAvailability.allowed() : enabled = true, reason = '';

  const ResumeAvailability.blocked(this.reason) : enabled = false;

  final bool enabled;

  /// Empty when [enabled]; otherwise the reason the action is unavailable.
  final String reason;
}
