import 'package:flutter/material.dart';

import 'app.dart';
import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/checkin_api.dart';
import 'data/demo_repository.dart';
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
      repository: DemoWdidRepository(),
      authApi: GrpcAuthApi(),
      categoryApiBuilder: (token) =>
          GrpcCategoryApi(rpc: GrpcCategoryRpc(token: token)),
      settingsApiBuilder: (token) =>
          GrpcSettingsApi(rpc: GrpcSettingsRpc(token: token)),
      entryApiBuilder: (token) => GrpcEntryApi(rpc: GrpcEntryRpc(token: token)),
      timerApiBuilder: (token) => GrpcTimerApi(rpc: GrpcTimerRpc(token: token)),
      summaryApiBuilder: (token) =>
          GrpcSummaryApi(rpc: GrpcSummaryRpc(token: token)),
      noteApiBuilder: (token) => GrpcNoteApi(rpc: GrpcNoteRpc(token: token)),
      milestoneApiBuilder: (token) =>
          GrpcMilestoneApi(rpc: GrpcMilestoneRpc(token: token)),
      checkInApiBuilder: (token) =>
          GrpcCheckInApi(rpc: GrpcCheckInRpc(token: token)),
    ),
  );
}
