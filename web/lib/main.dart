import 'package:flutter/material.dart';

import 'app.dart';
import 'data/demo_repository.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WdidApp(repository: DemoWdidRepository()));
}


