import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'state/assignment_store.dart';
import 'theme.dart';
import 'views/dashboard_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AssignmentStore(await StorageService.create());
  await store.load();
  runApp(DueTodayApp(store: store, api: ApiService()));
}

class DueTodayApp extends StatelessWidget {
  const DueTodayApp({super.key, required this.store, required this.api});

  final AssignmentStore store;
  final ApiService api;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AssignmentStore>.value(value: store),
        Provider<ApiService>.value(value: api),
      ],
      child: MaterialApp(
        title: 'DueToday',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const DashboardView(),
      ),
    );
  }
}
