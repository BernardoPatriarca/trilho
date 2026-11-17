import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trilho/core/db/database.dart';
import 'package:trilho/domain/notification_plan.dart';
import 'package:trilho/features/notifications/notification_scheduler.dart';

/// Banco SQLite em memória (sqflite_common_ffi), já migrado e com seeds.
Future<Database> openTestDb({bool noIsolate = false}) {
  sqfliteFfiInit();
  return openWithFactory(noIsolate ? databaseFactoryFfiNoIsolate : databaseFactoryFfi, inMemoryDatabasePath);
}

/// Fake do plugin: guarda o que está "agendado no Android".
class FakeGateway implements NotificationGateway {
  final Map<int, PlannedNotification> scheduled = {};
  final List<int> cancels = [];
  int scheduleCalls = 0;
  bool exact = true;

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<void> schedule(PlannedNotification n, {required bool exact}) async {
    scheduleCalls++;
    scheduled[n.id] = n;
  }

  @override
  Future<void> cancel(int id) async {
    cancels.add(id);
    scheduled.remove(id);
  }

  @override
  Future<void> cancelAll() async => scheduled.clear();

  List<PlannedNotification> ofKind(PlannedKind k) => scheduled.values.where((n) => n.kind == k).toList()
    ..sort((a, b) => a.fireAt.compareTo(b.fireAt));
}
