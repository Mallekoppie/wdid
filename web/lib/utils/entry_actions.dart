import 'package:flutter/material.dart';

import '../data/timer_api.dart';
import '../models/work_entry.dart';
import '../state/app_state_scope.dart';

/// Starts a timer attributed like [entry] and reports the outcome. Today and
/// Log share this so both Resume actions behave identically: a running timer is
/// refused by the shared path and is never paused, stopped or replaced.
Future<void> resumeWorkEntry(BuildContext context, WorkEntry entry) async {
  final state = AppStateScope.read(context);
  try {
    await state.resumeEntry(entry);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Timer started')),
    );
  } on TimerFailure catch (failure) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failure.message)));
  }
}
