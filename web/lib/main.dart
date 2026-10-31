import 'package:flutter/material.dart';

import 'app.dart';
import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/checkin_api.dart';
import 'data/entry_api.dart';
import 'data/milestone_api.dart';
import 'data/note_api.dart';
import 'data/settings_api.dart';
import 'data/summary_api.dart';
import 'data/timer_api.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    WdidApp(
      authApi: GrpcAuthApi(),
      categoryApiBuilder: (session) =>
          GrpcCategoryApi(rpc: GrpcCategoryRpc(session: session)),
      settingsApiBuilder: (session) =>
          GrpcSettingsApi(rpc: GrpcSettingsRpc(session: session)),
      entryApiBuilder: (session) =>
          GrpcEntryApi(rpc: GrpcEntryRpc(session: session)),
      timerApiBuilder: (session) =>
          GrpcTimerApi(rpc: GrpcTimerRpc(session: session)),
      summaryApiBuilder: (session) =>
          GrpcSummaryApi(rpc: GrpcSummaryRpc(session: session)),
      noteApiBuilder: (session) =>
          GrpcNoteApi(rpc: GrpcNoteRpc(session: session)),
      milestoneApiBuilder: (session) =>
          GrpcMilestoneApi(rpc: GrpcMilestoneRpc(session: session)),
      checkInApiBuilder: (session) =>
          GrpcCheckInApi(rpc: GrpcCheckInRpc(session: session)),
    ),
  );
}
