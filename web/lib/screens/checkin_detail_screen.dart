import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/check_in.dart';
import '../models/enums.dart';
import '../models/period_report.dart';
import '../theme/app_tokens.dart';
import '../utils/time_utils.dart';
import '../widgets/app_dropdown.dart';
import '../widgets/checkin_aggregates.dart';
import '../widgets/forms/checkin_dialog.dart';
import '../widgets/forms/export_dialog.dart';
import '../widgets/forms/prompt_dialog.dart';
import '../widgets/panel.dart';
import '../widgets/screen_states.dart';
import '../widgets/simple_markdown.dart';
import '../widgets/status_badge.dart';
import '../state/app_state.dart';
import '../state/app_state_scope.dart';

class CheckinDetailScreen extends StatefulWidget {
  const CheckinDetailScreen({super.key, required this.checkInId});

  final String checkInId;

  @override
  State<CheckinDetailScreen> createState() => _CheckinDetailScreenState();
}

class _CheckinDetailScreenState extends State<CheckinDetailScreen> {
  final _editor = TextEditingController();
  bool _requested = false;
  bool _editing = false;
  bool _generating = false;
  String _streamText = '';
  String? _generationError;
  bool _saving = false;
  bool _buildingPrompt = false;
  bool _updatingAudience = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppStateScope.read(context);
    if (!state.hasCheckInService || _requested) return;
    _requested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = AppStateScope.read(context);
      if (current.checkInDetailId != widget.checkInId) {
        unawaited(current.loadCheckInDetail(widget.checkInId));
      }
    });
  }

  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  Future<void> _generate(AppState state, CheckIn checkIn) async {
    if (checkIn.state == CheckInState.edited &&
        checkIn.summaryMarkdown.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace edited summary?'),
          content: const Text(
            'Generation will replace your manual edits. Copy the current summary '
            'first if you want to keep it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Regenerate'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() {
      _generating = true;
      _streamText = '';
      _generationError = null;
    });
    try {
      await for (final delta in state.generateSummaryStream(
        checkIn,
        overwriteManualEdits: true,
      )) {
        if (!mounted) return;
        if (delta.text.isEmpty) continue;
        setState(() => _streamText += delta.text);
      }
      if (!mounted) return;
      setState(() {
        _generating = false;
        _streamText = '';
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Summary generated')));
    } catch (error) {
      if (!mounted) return;
      // The service persists only a complete response, so the stored summary
      // is untouched. Drop the partial preview and offer an explicit retry.
      setState(() {
        _generating = false;
        _streamText = '';
        _generationError = error.toString();
      });
    }
  }

  Future<void> _saveSummary(AppState state, CheckIn checkIn) async {
    setState(() => _saving = true);
    try {
      await state.saveSummary(checkIn, _editor.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _editing = false;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Summary saved')));
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the summary: $error')),
      );
    }
  }

  Future<void> _copyPrompt(AppState state, CheckIn checkIn) async {
    setState(() => _buildingPrompt = true);
    try {
      final prompt = await state.buildCheckInPrompt(checkIn);
      if (!mounted) return;
      setState(() => _buildingPrompt = false);
      await showPromptDialog(context, prompt: prompt);
    } catch (error) {
      if (!mounted) return;
      setState(() => _buildingPrompt = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not build the prompt: $error')),
      );
    }
  }

  Future<void> _changeAudience(
    AppState state,
    CheckIn checkIn,
    CheckInAudience audience,
  ) async {
    if (checkIn.audience == audience) return;
    setState(() => _updatingAudience = true);
    try {
      await state.setCheckInAudience(checkIn, audience);
      if (!mounted) return;
      setState(() => _updatingAudience = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Audience set to ${audience.label}')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _updatingAudience = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not change the audience: $error')),
      );
    }
  }

  Future<void> _editReview(AppState state, CheckIn checkIn) async {
    final updated = await showPersonalReviewDialog(
      context,
      state: state,
      checkIn: checkIn,
    );
    if (updated == null || !mounted) return;
    unawaited(state.loadCheckInDetail(updated.id, force: true));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Review updated')));
  }

  Future<void> _deleteCheckIn(AppState state, CheckIn checkIn) async {
    final isReview = checkIn.isPersonal;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isReview
              ? 'Delete this personal review?'
              : 'Delete this draft check-in?',
        ),
        content: Text(
          isReview
              ? 'The review and its notes are removed. This never changes the '
                    'manager boundary.'
              : 'The draft check-in and its notes are removed. This never '
                    'changes the manager boundary.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isReview ? 'Delete review' : 'Delete draft check-in'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await state.deleteCheckIn(checkIn.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isReview ? 'Review deleted' : 'Draft check-in deleted'),
        ),
      );
      context.go('/checkins');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isReview
                ? 'Could not delete the review: $error'
                : 'Could not delete the draft check-in: $error',
          ),
        ),
      );
    }
  }

  Future<void> _finalize(AppState state, CheckIn checkIn) async {
    // A final check-in is read-only, so an open summary draft would be
    // stranded in an editor that can no longer save. Finish or cancel the
    // draft first.
    if (_editing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark check-in as final?'),
        content: const Text(
          'Final check-ins are read-only and become the boundary for the next '
          'period.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Mark final'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await state.finalizeCheckIn(checkIn);
      if (!mounted) return;
      setState(() => _editing = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Check-in marked final')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not finalize the check-in: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final checkIn = state.checkInById(widget.checkInId);

    if (state.hasCheckInService &&
        checkIn == null &&
        state.checkInDetailLoading) {
      return const ScreenBody(
        child: PageScaffold(child: Center(child: LoadingView())),
      );
    }
    // A cached listing copy must not hide a failed detail read: the retry
    // belongs on screen even when the list already knows this check-in.
    final detailFailed =
        state.checkInDetailId == widget.checkInId &&
        state.checkInDetail == null &&
        state.checkInDetailError != null;
    if (state.hasCheckInService && (checkIn == null || detailFailed)) {
      final error = state.checkInDetailError;
      return ScreenBody(
        child: PageScaffold(
          child: Panel(
            child: error == null
                ? EmptyState(
                    icon: Icons.event_note_outlined,
                    title: 'Check-in not found',
                    message: 'It may have been removed.',
                    action: FilledButton(
                      onPressed: () => context.go('/checkins'),
                      child: const Text('Back to check-ins'),
                    ),
                  )
                : EmptyState(
                    icon: Icons.cloud_off_outlined,
                    title: 'Could not load the check-in',
                    message: error,
                    action: OutlinedButton.icon(
                      onPressed: () => unawaited(
                        state.loadCheckInDetail(widget.checkInId, force: true),
                      ),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry'),
                    ),
                  ),
          ),
        ),
      );
    }
    if (checkIn == null) {
      return ScreenBody(
        child: PageScaffold(
          child: Panel(
            child: EmptyState(
              icon: Icons.event_note_outlined,
              title: 'Check-in not found',
              message: 'It may have been removed.',
              action: FilledButton(
                onPressed: () => context.go('/checkins'),
                child: const Text('Back to check-ins'),
              ),
            ),
          ),
        ),
      );
    }

    final report =
        state.checkInReport?.fromDate == isoDate(checkIn.periodStart) &&
            state.checkInReport?.toDate == isoDate(checkIn.periodEnd)
        ? state.checkInReport
        : null;
    final readOnly = checkIn.isReadOnly;

    return ScreenBody(
      child: PageScaffold(
        child: ListView(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  tooltip: 'Back to check-ins',
                  onPressed: () => context.go('/checkins'),
                  icon: const Icon(Icons.arrow_back, size: 18),
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: AppSpacing.sm,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Check-in · ${formatRange(checkIn.periodStart, checkIn.periodEnd)}',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontFeatures: tabularFigures,
                            ),
                          ),
                          CheckInKindBadge(kind: checkIn.kind),
                          if (checkIn.audience != null)
                            CheckInAudienceBadge(audience: checkIn.audience!),
                          CheckInStateBadge(state: checkIn.state),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Created ${formatFullDate(checkIn.createdAt)} · '
                        '${checkIn.daysCovered} days'
                        '${checkIn.summaryModel == null ? '' : ' · ${checkIn.summaryModel}'}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFeatures: tabularFigures,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                if (checkIn.isPersonal) ...[
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_editReview(state, checkIn)),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Edit review'),
                  ),
                  const SizedBox(width: 6),
                ],
                if (!checkIn.isFinal) ...[
                  OutlinedButton.icon(
                    onPressed: () => unawaited(_deleteCheckIn(state, checkIn)),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    label: Text(
                      checkIn.isPersonal
                          ? 'Delete review'
                          : 'Delete draft check-in',
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (state.canExport)
                  OutlinedButton.icon(
                    onPressed: () => showExportDialog(
                      context,
                      state: state,
                      start: checkIn.periodStart,
                      end: checkIn.periodEnd,
                      checkInId: checkIn.id,
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export'),
                  ),
                if (state.canExport) const SizedBox(width: 6),
                if (checkIn.canFinalize)
                  FilledButton.icon(
                    onPressed: _editing
                        ? null
                        : () => unawaited(_finalize(state, checkIn)),
                    icon: const Icon(Icons.flag_outlined, size: 16),
                    label: const Text('Mark final'),
                  ),
              ],
            ),
            if (readOnly) ...[
              const SizedBox(height: AppSpacing.md),
              Panel(
                tone: PanelTone.support,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.md,
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 17, color: scheme.tertiary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Final check-in — read-only boundary for the next period.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (checkIn.isPersonal) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Personal review — editable, and never moves the manager boundary.',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            _Stats(checkIn: checkIn, report: report),
            const SizedBox(height: AppSpacing.lg),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  PanelHeader(
                    title: 'Summary',
                    subtitle: _editing
                        ? 'Editing Markdown · generation will not overwrite silently'
                        : checkIn.summaryModel == null
                        ? 'No model recorded'
                        : 'Model: ${checkIn.summaryModel} · prompt ${checkIn.promptVersion}',
                    icon: Icons.auto_awesome_outlined,
                  ),
                  if (checkIn.isManager) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        SizedBox(
                          width: 210,
                          child: AppDropdown<CheckInAudience>(
                            value: checkIn.audience ?? CheckInAudience.oneOnOne,
                            label: 'Audience',
                            icon: Icons.forum_outlined,
                            enabled: !readOnly && !_updatingAudience,
                            items: const [
                              DropdownMenuItem(
                                value: CheckInAudience.oneOnOne,
                                child: Text('1:1'),
                              ),
                              DropdownMenuItem(
                                value: CheckInAudience.performanceReview,
                                child: Text('Performance review'),
                              ),
                            ],
                            onChanged: (audience) {
                              if (audience == null) return;
                              unawaited(
                                _changeAudience(state, checkIn, audience),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            'The audience selects the prompt variant. It never '
                            'changes the summary or the recorded data.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      if (!readOnly &&
                          !_editing &&
                          state.canGenerateSummary) ...[
                        FilledButton.tonalIcon(
                          onPressed: _generating
                              ? null
                              : () => unawaited(_generate(state, checkIn)),
                          icon: _generating
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome, size: 16),
                          label: Text(
                            checkIn.summaryMarkdown.isEmpty
                                ? 'Generate with AI'
                                : 'Regenerate',
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      OutlinedButton.icon(
                        onPressed: _buildingPrompt
                            ? null
                            : () => unawaited(_copyPrompt(state, checkIn)),
                        icon: _buildingPrompt
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.copy_all, size: 15),
                        label: const Text('Copy prompt'),
                      ),
                      const Spacer(),
                      if (!readOnly && !_editing)
                        TextButton.icon(
                          onPressed: () {
                            _editor.text = checkIn.summaryMarkdown;
                            setState(() => _editing = true);
                          },
                          icon: const Icon(Icons.edit_outlined, size: 15),
                          label: const Text('Edit'),
                        ),
                      if (!readOnly && _editing) ...[
                        TextButton(
                          onPressed: _saving
                              ? null
                              : () {
                                  setState(() => _editing = false);
                                },
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: _saving
                              ? null
                              : () => unawaited(_saveSummary(state, checkIn)),
                          child: _saving
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Save summary'),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_generationError != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 17,
                            color: scheme.onErrorContainer,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Generation failed. The existing summary is '
                              'unchanged. ${_generationError!}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: _generating
                                ? null
                                : () => unawaited(_generate(state, checkIn)),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  if (_generating)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Text(
                                'Generating with ${checkIn.summaryModel ?? 'the configured model'}…',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            _streamText.isEmpty
                                ? 'Waiting for the model…'
                                : _streamText,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontFamily: 'monospace',
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (_editing)
                    TextField(
                      controller: _editor,
                      minLines: 14,
                      maxLines: 24,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                        height: 1.5,
                      ),
                      decoration: const InputDecoration(
                        hintText: '## Highlights\n- …',
                      ),
                    )
                  else if (checkIn.summaryMarkdown.isEmpty)
                    EmptyState(
                      icon: Icons.auto_awesome_outlined,
                      title: 'No summary yet',
                      message: state.canGenerateSummary
                          ? 'Generate one from the captured entries, or copy the '
                                'prompt into your own model.'
                          : state.hasSummaryService
                          ? 'Add your AI provider key in Settings → AI to '
                                'generate a summary, or copy the prompt into your '
                                'own model.'
                          : 'Add a summary for this period, or copy the focus notes into your own review.',
                      action: readOnly || !state.canGenerateSummary
                          ? null
                          : FilledButton.icon(
                              onPressed: _generating
                                  ? null
                                  : () => unawaited(_generate(state, checkIn)),
                              icon: const Icon(Icons.auto_awesome, size: 16),
                              label: const Text('Generate with AI'),
                            ),
                    )
                  else
                    SimpleMarkdown(checkIn.summaryMarkdown),
                  // A missing key hides the Regenerate action. Keep the reason
                  // visible next to an existing summary too, instead of leaving
                  // the user to wonder why the action disappeared.
                  if (!_editing &&
                      checkIn.summaryMarkdown.isNotEmpty &&
                      state.hasSummaryService &&
                      !state.settings.hasAiApiKey) ...[
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(AppRadius.input),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.key_outlined,
                            size: 17,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Add your AI provider key in Settings → AI to '
                              'generate a summary, or copy the prompt into '
                              'your own model.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (checkIn.focusNotes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    PanelHeader(
                      title: 'Focus notes',
                      icon: Icons.push_pin_outlined,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(checkIn.focusNotes, style: theme.textTheme.bodyMedium),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            CheckInAggregates(state: state, report: report),
            if (!state.hasCheckInService) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () => showExportDialog(
                      context,
                      state: state,
                      start: checkIn.periodStart,
                      end: checkIn.periodEnd,
                      checkInId: checkIn.id,
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('Export summary.md + data.json'),
                  ),
                  const Spacer(),
                  if (checkIn.canFinalize)
                    OutlinedButton.icon(
                      onPressed: _editing
                          ? null
                          : () => unawaited(_finalize(state, checkIn)),
                      icon: const Icon(Icons.flag_outlined, size: 16),
                      label: const Text('Mark as final'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Stats extends StatelessWidget {
  const _Stats({required this.checkIn, required this.report});

  final CheckIn checkIn;
  final PeriodReport? report;

  @override
  Widget build(BuildContext context) {
    final report = this.report;
    // Live totals come from the report; the snapshot fallback carries the
    // authoritative values captured at creation. Neither sums per-person rows.
    final supportMinutes =
        report?.supportMinutes ?? checkIn.totals.supportMinutes;
    final interactions =
        report?.supportInteractions ?? checkIn.totals.supportInteractions;
    return Wrap(
      spacing: AppSpacing.xl,
      runSpacing: AppSpacing.md,
      children: [
        _Stat(
          label: 'logged',
          value: formatDuration(report?.totalMinutes ?? checkIn.totals.minutes),
        ),
        _Stat(label: 'days', value: '${checkIn.daysCovered}'),
        if (report != null)
          _Stat(label: 'entries', value: '${report.entryCount}'),
        _Stat(label: 'support', value: formatDuration(supportMinutes)),
        _Stat(label: 'interactions', value: '$interactions'),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontFeatures: tabularFigures,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
