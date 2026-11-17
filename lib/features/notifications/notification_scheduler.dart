// Agendador idempotente das notificações.
//
// A tabela `notificacao_agendada` é a fonte da verdade do que está agendado
// no Android. A cada `sync()`:
//   1. monta o plano (domínio) dos próximos 30 dias, com teto de 400;
//   2. cancela o que saiu do plano ou mudou (assinatura diferente);
//   3. agenda o que falta;
//   4. grava a tabela.
// Rodar duas vezes seguidas não mexe em nada na segunda.
import 'package:sqflite/sqflite.dart';

import '../../domain/daily_summary.dart';
import '../../domain/dates.dart';
import '../../domain/event_expansion.dart';
import '../../domain/models.dart';
import '../../domain/notification_plan.dart';
import '../events/event_repository.dart';
import '../settings/config_repository.dart';

/// O que o agendador precisa do plugin (o fake dos testes implementa isto).
abstract class NotificationGateway {
  Future<bool> canScheduleExact();
  Future<void> schedule(PlannedNotification n, {required bool exact});
  Future<void> cancel(int id);
  Future<void> cancelAll();
}

class SyncReport {
  const SyncReport({required this.scheduled, required this.cancelled, required this.total, required this.exact});
  final int scheduled;
  final int cancelled;
  final int total;
  final bool exact;
}

/// Linha da tabela, para a tela de diagnóstico.
class ScheduledRow {
  const ScheduledRow({
    required this.id,
    required this.kind,
    required this.fireAt,
    this.title,
    this.targetType,
    this.targetId,
  });
  final int id;
  final String kind;
  final DateTime fireAt;
  final String? title;
  final String? targetType;
  final int? targetId;
}

class NotificationScheduler {
  NotificationScheduler(this.db, this.gateway, {DateTime Function()? clock}) : clock = clock ?? DateTime.now;
  final Database db;
  final NotificationGateway gateway;
  final DateTime Function() clock;

  Future<List<PlannedNotification>> buildPlan(DateTime now) async {
    final config = await ConfigRepository(db).load();
    final today = dateOnly(now);

    // Tarefas pendentes (todas: o resumo precisa das sem lembrete também).
    final tasks = (await db.query('tarefa', where: "status = 'pendente'")).map(Task.fromRow).toList();
    final remindersByTask = <int, List<Reminder>>{};
    for (final r in await db.query('lembrete', where: "alvo_tipo = 'tarefa'", orderBy: 'id')) {
      final rem = Reminder.fromRow(r);
      remindersByTask.putIfAbsent(rem.targetId!, () => []).add(rem);
    }
    final progress = <int, ChecklistProgress>{
      for (final r in await db.rawQuery(
        'SELECT tarefa_id, SUM(marcado) AS m, COUNT(*) AS n FROM checklist_item GROUP BY tarefa_id',
      ))
        r['tarefa_id'] as int: ChecklistProgress((r['m'] as int?) ?? 0, r['n'] as int),
    };

    // Eventos da janela (inclui um dia antes para eventos que começam antes
    // e têm lembrete com antecedência).
    final windowEnd = addDays(today, notificationWindowDays + 1);
    final events = EventRepository(db);
    final series = await events.seriesInRange(today, windowEnd);
    final eventReminders = await events.allReminders();
    final occurrences = <EventOccurrence>[];
    final eventInputs = <EventReminderInput>[];
    for (final s in series) {
      final occ = expandEvents([s], today, windowEnd);
      occurrences.addAll(occ);
      final rem = eventReminders[s.event.id] ?? const [];
      if (occ.isNotEmpty && rem.isNotEmpty) eventInputs.add(EventReminderInput(occ, rem));
    }

    final summaries = <SummaryInput>[];
    if (config.summaryEnabled) {
      for (var k = 0; k < summaryDays + 1; k++) {
        final day = addDays(today, k);
        final at = atMinutes(day, config.summaryMinutes);
        if (!at.isAfter(now) || summaries.length >= summaryDays) continue;
        final s = buildDailySummary(day: day, tasks: tasks, events: occurrences, checklist: progress);
        summaries.add(SummaryInput(at, s.title, s.body));
      }
    }

    DateTime? backupAt;
    if (config.weeklyBackupReminder) {
      // Domingo às 20h (o próximo que ainda não passou).
      var sunday = today.weekday == DateTime.sunday ? today : nextWeekday(today, DateTime.sunday);
      if (!atMinutes(sunday, 20 * 60).isAfter(now)) sunday = addDays(sunday, 7);
      backupAt = atMinutes(sunday, 20 * 60);
    }

    return planNotifications(
      now: now,
      tasks: [
        for (final t in tasks)
          if (remindersByTask[t.id]?.isNotEmpty ?? false)
            TaskReminderInput(t, remindersByTask[t.id]!, checklist: progress[t.id] ?? ChecklistProgress.empty),
      ],
      events: eventInputs,
      summaries: summaries,
      defaultTaskMinutes: config.defaultTaskMinutes,
      backupReminderAt: backupAt,
    );
  }

  Future<SyncReport> sync() async {
    final now = clock();
    final exact = await gateway.canScheduleExact();
    final plan = await buildPlan(now);
    final rows = await db.query('notificacao_agendada');

    final planned = {for (final n in plan) n.id: n};
    var cancelled = 0, scheduled = 0;
    final keep = <int>{};

    // Ids de tarefas que não estão mais pendentes (para tirar da bandeja
    // os lembretes que já dispararam).
    final closedTasks = {
      for (final r in await db.query('tarefa', columns: ['id'], where: "status <> 'pendente'")) r['id'] as int,
    };
    final existingTasks = {
      for (final r in await db.query('tarefa', columns: ['id'])) r['id'] as int,
    };

    for (final r in rows) {
      final id = r['notification_id'] as int;
      final kind = r['tipo'] as String;
      final fireAt = fromIsoDateTime(r['dispara_em'] as String);
      if (kind == 'teste') {
        if (fireAt.isAfter(now)) keep.add(id);
        continue;
      }
      if (!fireAt.isAfter(now)) {
        // Já disparou: só sai da tabela. Se a tarefa foi concluída ou
        // excluída, remove também da bandeja.
        final taskId = r['alvo_tipo'] == 'tarefa' ? r['alvo_id'] as int? : null;
        if (taskId != null && (closedTasks.contains(taskId) || !existingTasks.contains(taskId))) {
          await gateway.cancel(id);
        }
        continue;
      }
      final n = planned[id];
      if (n == null || n.signature(exact: exact) != r['assinatura']) {
        await gateway.cancel(id);
        cancelled++;
        continue;
      }
      keep.add(id);
    }

    final toWrite = <PlannedNotification>[];
    for (final n in plan) {
      if (keep.contains(n.id)) continue;
      await gateway.schedule(n, exact: exact);
      scheduled++;
      toWrite.add(n);
    }

    await db.transaction((txn) async {
      if (keep.isEmpty) {
        await txn.delete('notificacao_agendada');
      } else {
        await txn.delete('notificacao_agendada', where: 'notification_id NOT IN (${keep.join(',')})');
      }
      for (final n in toWrite) {
        await txn.insert('notificacao_agendada', _row(n, exact), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    return SyncReport(scheduled: scheduled, cancelled: cancelled, total: keep.length + toWrite.length, exact: exact);
  }

  Map<String, Object?> _row(PlannedNotification n, bool exact) => {
    'notification_id': n.id,
    'tipo': n.kind.name,
    'alvo_tipo': n.targetType?.name,
    'alvo_id': n.targetId,
    'ocorrencia': n.occurrence == null ? null : toIsoDate(n.occurrence!),
    'dispara_em': toIsoDateTime(n.fireAt),
    'titulo': n.title,
    'assinatura': n.signature(exact: exact),
  };

  /// "Reagendar tudo": cancela todas e agenda de novo.
  Future<SyncReport> rescheduleAll() async {
    await gateway.cancelAll();
    await db.delete('notificacao_agendada');
    return sync();
  }

  /// "Testar lembrete em 1 minuto".
  Future<DateTime> scheduleTest() async {
    final now = clock();
    final at = DateTime(now.year, now.month, now.day, now.hour, now.minute).add(const Duration(minutes: 1, seconds: 0));
    final fireAt = at.isAfter(now.add(const Duration(seconds: 30))) ? at : at.add(const Duration(minutes: 1));
    final n = PlannedNotification(
      id: testNotificationId,
      kind: PlannedKind.teste,
      fireAt: fireAt,
      title: 'Teste do Trilho',
      body: 'Se você está lendo isto, os lembretes estão funcionando. ✔',
      payload: 'diagnostico',
    );
    final exact = await gateway.canScheduleExact();
    await gateway.cancel(testNotificationId);
    await gateway.schedule(n, exact: exact);
    await db.insert('notificacao_agendada', _row(n, exact), conflictAlgorithm: ConflictAlgorithm.replace);
    return fireAt;
  }

  Future<List<ScheduledRow>> upcoming({int limit = 100}) async {
    final rows = await db.query(
      'notificacao_agendada',
      where: 'dispara_em > ?',
      whereArgs: [toIsoDateTime(clock())],
      orderBy: 'dispara_em',
      limit: limit,
    );
    return [
      for (final r in rows)
        ScheduledRow(
          id: r['notification_id'] as int,
          kind: r['tipo'] as String,
          fireAt: fromIsoDateTime(r['dispara_em'] as String),
          title: r['titulo'] as String?,
          targetType: r['alvo_tipo'] as String?,
          targetId: r['alvo_id'] as int?,
        ),
    ];
  }

  Future<int> scheduledCount() async =>
      (await db.rawQuery('SELECT COUNT(*) AS n FROM notificacao_agendada WHERE dispara_em > ?', [
            toIsoDateTime(clock()),
          ])).first['n']
          as int;
}
