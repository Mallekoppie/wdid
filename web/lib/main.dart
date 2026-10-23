import 'package:flutter/material.dart';

import 'app.dart';
import 'data/auth_api.dart';
import 'data/category_api.dart';
import 'data/demo_repository.dart';
import 'data/settings_api.dart';

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
    ),
  );
}
