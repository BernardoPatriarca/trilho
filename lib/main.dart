// Trilho — o caminho que mantém o seu dia no curso. App pessoal, 100% offline.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'core/db/database.dart';
import 'core/providers.dart';
import 'features/notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  final db = await openTrilhoDatabase();
  final notifications = LocalNotificationGateway();
  await notifications.initialize(
    onTap: (r) {
      // Toque na notificação (app aberto ou em segundo plano): abre o item.
      final route = routeForPayload(r.payload);
      if (route != null) pendingRoute.value = route;
    },
  );
  // App aberto pelo toque numa notificação.
  pendingRoute.value = routeForPayload(await notifications.launchPayload());

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), notificationGatewayProvider.overrideWithValue(notifications)],
      child: const TrilhoApp(),
    ),
  );
}
