// Ações das notificações de tarefa ("Concluir" e "Adiar 1h") executadas sem
// abrir o app. O plugin chama esta função num isolate de segundo plano:
// abre o banco, aplica a ação, reagenda tudo e mostra uma confirmação curta.
import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/db/database.dart';
import '../../domain/dates.dart';
import '../tasks/task_repository.dart';
import 'notification_scheduler.dart';
import 'notification_service.dart';

/// Id da notificação de confirmação ("Concluída: ...").
const _confirmationId = 2;

@pragma('vm:entry-point')
Future<void> notificationActionBackground(NotificationResponse response) async {
  DartPluginRegistrant.ensureInitialized();
  Database? db;
  try {
    db = await openTrilhoDatabase();
    final gateway = LocalNotificationGateway();
    await gateway.plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notificacao')),
    );
    await initTimezone();
    final message = await applyNotificationAction(db, response.actionId, response.payload, DateTime.now());
    await NotificationScheduler(db, gateway).sync();
    if (message != null) await gateway.showNow(_confirmationId, message.$1, message.$2);
  } finally {
    await db?.close();
  }
}

/// Aplica a ação no banco. Retorna (título, texto) da confirmação, ou null.
/// Separado do handler para ser testável.
Future<(String, String)?> applyNotificationAction(Database db, String? actionId, String? payload, DateTime now) async {
  if (payload == null || !payload.startsWith('tarefa:')) return null;
  final id = int.tryParse(payload.substring(7));
  if (id == null) return null;
  final repo = TaskRepository(db);
  final details = await repo.get(id);
  if (details == null || !details.task.isPending) return null;
  switch (actionId) {
    case actionComplete:
      final r = await repo.complete(id, now);
      return ('Concluída ✔', r.nextId == null ? details.task.title : '${details.task.title} · próxima já agendada');
    case actionSnooze:
      final at = now.add(const Duration(hours: 1));
      await repo.postponeTo(id, dateOnly(at), minutesOfDay(at), now);
      return ('Adiada para ${hm(at)}', details.task.title);
  }
  return null;
}
