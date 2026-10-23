import 'package:flutter/material.dart';

import 'app.dart';
import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/demo_repository.dart';
import 'data/entry_api.dart';
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
    ),
  );
}
