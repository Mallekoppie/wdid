import 'package:flutter/material.dart';

import '../models/taxonomy.dart';
import '../state/app_state.dart';
import '../widgets/forms/project_dialog.dart';

/// Opens the shared project form for [project] and reports a successful save.
/// The Initiatives card menu and the project detail header both use it, so the
/// dialog and its snackbar cannot drift.
Future<void> editProject(
  BuildContext context, {
  required AppState state,
  required Subcategory project,
}) async {
  final saved = await showProjectDialog(
    context,
    state: state,
    project: project,
  );
  if (saved == null || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Project updated · ${saved.name}')),
  );
}
