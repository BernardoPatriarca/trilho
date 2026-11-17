import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trilho/domain/dates.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/domain/notification_plan.dart';
import 'package:trilho/features/events/event_repository.dart';
import 'package:trilho/features/notifications/notification_scheduler.dart';
import 'package:trilho/features/settings/config_repository.dart';
import 'package:trilho/features/tasks/task_repository.dart';

import 'test_db.dart';

void main() {
  late Database db;
  late FakeGateway gw;
  late DateTime now;
  late NotificationScheduler scheduler;
  late TaskRepository tasks;
  late EventRepository events;

  setUp(() async {
    db = await openTestDb();
    gw = FakeGateway();
    now = DateTime(2026, 11, 17, 10); // terça
    scheduler = NotificationScheduler(db, gw, clock: () => now);
    tasks = TaskRepository(db);
    events = EventRepository(db);
  });
  tearDown(() => db.close());

  Task t(String title, {DateTime? due, int? min, int p = 4}) =>
      Task(title: title, dueDate: due, dueMinutes: min, priority: p, createdAt: now, updatedAt: now);

  test('lembrete de tarefa com hora e só com data (9h padrão)', () async {
    await tasks.save(TaskDraft(task: t('Prender o varão', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    await tasks.save(TaskDraft(task: t('Pagar conta', due: DateTime(2026, 11, 19))), now: now);
    await scheduler.sync();
    final rem = gw.ofKind(PlannedKind.lembrete);
    expect(rem.map((n) => toIsoDateTime(n.fireAt)), ['2026-11-18T18:00', '2026-11-19T09:00']);
    expect(rem.first.isTaskReminder, isTrue);
    expect(rem.first.payload, startsWith('tarefa:'));
    expect(rem.first.body, contains('Prazo: hoje às 18:00'));
  });

  test('resumos dos próximos 7 dias às 7h, com conteúdo do dia', () async {
    await tasks.save(TaskDraft(task: t('Relatório', due: DateTime(2026, 11, 18), p: 1)), now: now);
    await scheduler.sync();
    final res = gw.ofKind(PlannedKind.resumo);
    expect(res, hasLength(7));
    // Hoje às 7h já passou: começa amanhã.
    expect(toIsoDateTime(res.first.fireAt), '2026-11-18T07:00');
    expect(res.first.title, 'Bom dia! Hoje: 1 tarefa');
    expect(res.first.body, 'P1 · Relatório');
    expect(res[1].body, contains('1 tarefa atrasada'));
    expect(res.last.fireAt, DateTime(2026, 11, 24, 7));
  });

  test('idempotente: a segunda sincronização não mexe em nada', () async {
    await tasks.save(TaskDraft(task: t('a', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    final r1 = await scheduler.sync();
    final calls = gw.scheduleCalls;
    final r2 = await scheduler.sync();
    expect(r1.scheduled, greaterThan(0));
    expect(r2.scheduled, 0);
    expect(r2.cancelled, 0);
    expect(gw.scheduleCalls, calls);
    expect(r2.total, r1.total);
    expect((await db.query('notificacao_agendada')).length, r1.total);
  });

  test('ids determinísticos e estáveis entre sincronizações', () async {
    await tasks.save(TaskDraft(task: t('a', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    await scheduler.sync();
    final ids = gw.scheduled.keys.toSet();
    await scheduler.rescheduleAll();
    expect(gw.scheduled.keys.toSet(), ids);
  });

  test('concluir cancela o lembrete na hora', () async {
    final id = await tasks.save(TaskDraft(task: t('a', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    await scheduler.sync();
    final remId = gw.ofKind(PlannedKind.lembrete).single.id;
    await tasks.complete(id, now);
    await scheduler.sync();
    expect(gw.ofKind(PlannedKind.lembrete), isEmpty);
    expect(gw.cancels, contains(remId));
  });

  test('editar a hora reagenda só o que mudou', () async {
    final id = await tasks.save(TaskDraft(task: t('a', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    await scheduler.sync();
    final d = (await tasks.get(id))!;
    await tasks.save(TaskDraft(task: d.task.copyWith(dueMinutes: 20 * 60), reminders: d.reminders, remindersTouched: true), now: now);
    final r = await scheduler.sync();
    expect(gw.ofKind(PlannedKind.lembrete).single.fireAt, DateTime(2026, 11, 18, 20));
    // Lembrete + resumo do dia 18 (título igual; corpo igual) → só o lembrete muda.
    expect(r.cancelled, 1);
    expect(r.scheduled, 1);
  });

  test('resumo é recalculado quando algo muda no dia', () async {
    await scheduler.sync();
    final before = gw.ofKind(PlannedKind.resumo).first;
    expect(before.body, 'Dia livre na agenda. Que tal adiantar algo da semana?');
    await events.save(EventDraft(event: Event(title: 'Dentista', start: DateTime(2026, 11, 18, 14, 30), end: DateTime(2026, 11, 18, 15, 30), createdAt: now, updatedAt: now)), now: now);
    await scheduler.sync();
    final after = gw.ofKind(PlannedKind.resumo).first;
    expect(after.id, before.id);
    expect(after.title, 'Bom dia! Hoje: 1 evento');
    expect(after.body, '14:30 · Dentista');
  });

  test('evento recorrente: um lembrete por ocorrência dentro de 30 dias', () async {
    await events.save(
      EventDraft(
        event: Event(title: 'Aula', start: DateTime(2026, 11, 2, 9), end: DateTime(2026, 11, 2, 10), createdAt: now, updatedAt: now),
        rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1, 3]),
      ),
      now: now,
      defaultReminderMin: 15,
    );
    await scheduler.sync();
    final rem = gw.ofKind(PlannedKind.lembrete);
    // De 18/11 (qua) a 16/12 (qua): 9 ocorrências.
    expect(rem.first.fireAt, DateTime(2026, 11, 18, 8, 45));
    expect(rem.length, 9);
    expect(rem.every((n) => n.fireAt.isBefore(now.add(const Duration(days: 30)))), isTrue);
    expect(rem.map((n) => n.id).toSet(), hasLength(9));
    expect(rem.first.isTaskReminder, isFalse);
  });

  test('teto de 400 notificações', () async {
    await events.save(
      EventDraft(
        event: Event(title: 'Remédio', start: DateTime(2026, 11, 1, 0, 30), end: DateTime(2026, 11, 1, 0, 45), createdAt: now, updatedAt: now),
        rule: const RecurrenceRule(freq: Freq.diaria),
        reminders: [for (var m = 0; m < 20; m++) Reminder.relative(m)],
        remindersTouched: true,
      ),
      now: now,
    );
    final r = await scheduler.sync();
    expect(r.total, notificationCap);
    expect(gw.scheduled, hasLength(notificationCap));
    // Os resumos entram primeiro.
    expect(gw.ofKind(PlannedKind.resumo), hasLength(7));
  });

  test('resumo desligado e hora configurável', () async {
    final c = ConfigRepository(db);
    await c.set(ConfigRepository.summaryTime, '06:30');
    await scheduler.sync();
    expect(gw.ofKind(PlannedKind.resumo).first.fireAt, DateTime(2026, 11, 18, 6, 30));
    await c.set(ConfigRepository.summaryEnabled, '0');
    await scheduler.sync();
    expect(gw.ofKind(PlannedKind.resumo), isEmpty);
  });

  test('sem alarme exato: agenda inexato e reagenda quando a permissão chega', () async {
    gw.exact = false;
    await tasks.save(TaskDraft(task: t('a', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    final r1 = await scheduler.sync();
    expect(r1.exact, isFalse);
    gw.exact = true;
    final r2 = await scheduler.sync();
    expect(r2.exact, isTrue);
    expect(r2.scheduled, r1.total);
  });

  test('o tempo passa: notificações disparadas saem da tabela e a janela anda', () async {
    await tasks.save(TaskDraft(task: t('a', due: DateTime(2026, 11, 18), min: 18 * 60)), now: now);
    await scheduler.sync();
    now = DateTime(2026, 11, 19, 8);
    final r = await scheduler.sync();
    final rows = await scheduler.upcoming();
    expect(rows.every((x) => x.fireAt.isAfter(now)), isTrue);
    expect(rows.where((x) => x.kind == 'lembrete'), isEmpty);
    expect(r.total, rows.length);
    expect(rows.last.fireAt, DateTime(2026, 11, 26, 7)); // 7 resumos: 20 a 26/11
  });

  test('lembrete semanal de backup no domingo à noite', () async {
    await ConfigRepository(db).set(ConfigRepository.weeklyBackup, '1');
    await scheduler.sync();
    expect(gw.ofKind(PlannedKind.backup).single.fireAt, DateTime(2026, 11, 22, 20));
  });

  test('testar lembrete em 1 minuto', () async {
    final at = await scheduler.scheduleTest();
    expect(at, DateTime(2026, 11, 17, 10, 1));
    expect(gw.scheduled[testNotificationId], isNotNull);
    await scheduler.sync();
    expect(gw.scheduled[testNotificationId], isNotNull); // sync não mexe no teste
  });
}
