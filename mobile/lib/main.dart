import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'state/assignment_store.dart';
import 'theme/app_theme.dart';
import 'views/dashboard_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Plus Jakarta Sans is bundled (see pubspec.yaml); its OFL license must
  // ship with the app and appear in the licenses page.
  LicenseRegistry.addLicense(() async* {
    final license = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(['Plus Jakarta Sans'], license);
  });

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
        themeMode: ThemeMode.system,
        home: const DashboardView(),
      ),
    );
  }
}
