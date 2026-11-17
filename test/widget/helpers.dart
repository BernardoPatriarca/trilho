import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trilho/app/app.dart';
import 'package:trilho/core/db/database.dart';
import 'package:trilho/core/providers.dart';
import 'package:trilho/features/settings/config_repository.dart';
import 'package:trilho/features/settings/pin_service.dart';

import '../data/test_db.dart';

/// Terça-feira, 17/11/2026, 9h.
final fixedNow = DateTime(2026, 11, 17, 9);

/// Banco em memória sem isolate (funciona com o relógio falso dos widget
/// tests), com onboarding concluído.
Future<Database> openWidgetDb({bool onboarded = true}) async {
  sqfliteFfiInit();
  final db = await openWithFactory(databaseFactoryFfiNoIsolate, inMemoryDatabasePath);
  if (onboarded) await ConfigRepository(db).set(ConfigRepository.onboarded, '1');
  return db;
}

Future<FakeGateway> pumpApp(WidgetTester tester, Database db, {PinStore? pins}) async {
  Intl.defaultLocale = 'pt_BR';
  await initializeDateFormatting('pt_BR');
  final gw = FakeGateway();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => fixedNow),
      notificationGatewayProvider.overrideWithValue(gw),
      pinStoreProvider.overrideWithValue(pins ?? MemoryPinStore()),
    ],
    child: const TrilhoApp(),
  ));
  await settle(tester);
  return gw;
}

/// pumpAndSettle com limite (indicadores indeterminados não param).
Future<void> settle(WidgetTester tester, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Rola até o widget e toca nele.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester, 6);
}
