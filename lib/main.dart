import 'package:flutter/material.dart';
import 'backend.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MySqlApiService.instance.restoreSession();
  runApp(const LeafAndLoreApp());
}
