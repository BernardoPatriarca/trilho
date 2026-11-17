import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:trilho/core/db/schema.dart';
import 'package:trilho/domain/dates.dart';
import 'package:trilho/domain/event_expansion.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/domain/search.dart';
import 'package:trilho/features/categories/category_repository.dart';
import 'package:trilho/features/events/event_repository.dart';
import 'package:trilho/features/notifications/background_actions.dart';
import 'package:trilho/features/notifications/notification_service.dart';
import 'package:trilho/features/search/search_repository.dart';
import 'package:trilho/features/settings/backup_service.dart';
import 'package:trilho/features/settings/config_repository.dart';
import 'package:trilho/features/settings/pin_service.dart';
import 'package:trilho/features/tasks/task_repository.dart';
import 'package:trilho/features/templates/template_repository.dart';

import 'test_db.dart';

final now = DateTime(2026, 11, 17, 10);
final today = DateTime(2026, 11, 17);

Task newTask(String title, {DateTime? due, int? min, int priority = 4, int? cat}) => Task(
  title: title,
  dueDate: due,
  dueMinutes: min,
  priority: priority,
  categoryId: cat,
  createdAt: now,
  updatedAt: now,
);

Event newEvent(String title, DateTime start, DateTime end, {bool allDay = false}) =>
    Event(title: title, start: start, end: end, allDay: allDay, createdAt: now, updatedAt: now);

void main() {
  late Database db;
  late TaskRepository tasks;
  late EventRepository events;

  setUp(() async {
    db = await openTestDb();
    tasks = TaskRepository(db);
    events = EventRepository(db);
  });
  tearDown(() => db.close());

  group('schema e seeds', () {
    test('todas as tabelas existem e as chaves estrangeiras estão ligadas', () async {
      final names = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'"))
          .map((r) => r['name'])
          .toSet();
      expect(names, containsAll(tablesInOrder));
      expect((await db.rawQuery('PRAGMA foreign_keys')).first.values.first, 1);
      final idx = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_%'")).length;
      expect(idx, 5);
    });

    test('seeds: 7 categorias, modelo Mercado com 11 itens e config', () async {
      final cats = await CategoryRepository(db).all();
      expect(cats.map((c) => c.name), ['Trabalho', 'Estudo', 'Casa', 'Pessoal', 'Saúde', 'Finanças', 'Compras']);
      expect(cats.last.icon, 'shopping_cart');
      final t = await TemplateRepository(db).all();
      expect(t.single.name, 'Mercado');
      expect(t.single.items, hasLength(11));
      final c = await ConfigRepository(db).load();
      expect(c.summaryMinutes, 7 * 60);
      expect(c.defaultEventReminder, 15);
      expect(c.defaultTaskMinutes, 9 * 60);
      expect(c.postponeMinutes, 60);
      expect(c.theme, 'sistema');
      expect(c.pinEnabled, isFalse);
      expect(c.mondayFirst, isTrue);
    });

    test('CHECK do banco: hora só com data', () async {
      expect(
        () => db.insert('tarefa', {
          'titulo': 'x',
          'hora_prazo': '10:00',
          'criada_em': '2026-01-01T00:00',
          'atualizada_em': '2026-01-01T00:00',
        }),
        throwsA(isA<DatabaseException>()),
      );
    });
  });

  group('tarefas', () {
    test('salvar com checklist, tags e lembrete padrão; busca inclui itens', () async {
      final id = await tasks.save(
        TaskDraft(
          task: newTask('Ir ao mercado', due: DateTime(2026, 11, 18), min: 18 * 60, priority: 2, cat: 7),
          checklist: const [
            ChecklistItem(text: 'Óleo', quantity: '1'),
            ChecklistItem(text: 'Açúcar', quantity: '2 kg'),
          ],
          tagNames: const ['Casa', '#casa', 'semanal'],
        ),
        now: now,
      );
      final d = (await tasks.get(id))!;
      expect(d.task.title, 'Ir ao mercado');
      expect(d.checklist.map((i) => i.text), ['Óleo', 'Açúcar']);
      expect(d.checklist.last.quantity, '2 kg');
      expect(d.tags.map((t) => t.name), ['casa', 'semanal']);
      expect(d.reminders.single.offsetMin, 0);

      final res = await SearchRepository(db).search(const SearchCriteria(text: 'oleo'), now);
      expect(res.tasks.single.id, id);
    });

    test('validação em português', () async {
      expect(() => tasks.save(TaskDraft(task: newTask('  ')), now: now), throwsA(isA<ValidationException>()));
      expect(
        () => tasks.save(TaskDraft(task: newTask('x', min: 60)), now: now),
        throwsA(predicate((e) => '$e' == 'A hora do prazo precisa de uma data.')),
      );
    });

    test('editar checklist mantém ids e atualiza a busca', () async {
      final id = await tasks.save(
        TaskDraft(
          task: newTask('Lista'),
          checklist: const [ChecklistItem(text: 'pão')],
        ),
        now: now,
      );
      final d = (await tasks.get(id))!;
      await tasks.save(
        TaskDraft(
          task: d.task,
          checklist: [
            d.checklist.first.copyWith(checked: true),
            const ChecklistItem(text: 'café'),
          ],
          remindersTouched: true,
        ),
        now: now,
      );
      final d2 = (await tasks.get(id))!;
      expect(d2.checklist.first.id, d.checklist.first.id);
      expect(d2.checklist.first.checked, isTrue);
      expect((await SearchRepository(db).search(const SearchCriteria(text: 'café'), now)).tasks, hasLength(1));
    });

    test('concluir recorrente cria a próxima instância com checklist zerada, tags e lembretes', () async {
      final id = await tasks.save(
        TaskDraft(
          task: newTask('Mercado semanal', due: DateTime(2026, 11, 16), min: 18 * 60),
          checklist: const [
            ChecklistItem(text: 'arroz', checked: true),
            ChecklistItem(text: 'leite'),
          ],
          tagNames: const ['casa'],
          reminders: const [Reminder.relative(30)],
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1]),
          remindersTouched: true,
        ),
        now: now,
      );
      final r = await tasks.complete(id, now);
      expect(r.nextId, isNotNull);
      final done = (await tasks.get(id))!.task;
      expect(done.status, TaskStatus.concluida);
      expect(done.completedAt, now);
      final next = (await tasks.get(r.nextId!))!;
      expect(next.task.dueDate, DateTime(2026, 11, 23)); // do prazo original, não da conclusão
      expect(next.task.dueMinutes, 18 * 60);
      expect(next.checklist.map((i) => i.checked), [false, false]);
      expect(next.tags.single.name, 'casa');
      expect(next.reminders.single.offsetMin, 30);
      expect(next.rule!.freq, Freq.semanal);

      // Desfazer apaga a próxima e reabre.
      await tasks.undoComplete(r);
      expect((await tasks.get(id))!.task.status, TaskStatus.pendente);
      expect(await tasks.get(r.nextId!), isNull);
    });

    test('adiar incrementa adiamentos e desfazer restaura', () async {
      final id = await tasks.save(
        TaskDraft(
          task: newTask('Prender o varão', due: today, min: 9 * 60),
        ),
        now: now,
      );
      final before = await tasks.postponeTo(id, today, 19 * 60, now);
      final t = (await tasks.get(id))!.task;
      expect(t.dueMinutes, 19 * 60);
      expect(t.postponements, 1);
      await tasks.restore(before);
      expect((await tasks.get(id))!.task.postponements, 0);
    });

    test('reagendar atrasadas para hoje', () async {
      await tasks.save(
        TaskDraft(task: newTask('a', due: DateTime(2026, 11, 10))),
        now: now,
      );
      await tasks.save(
        TaskDraft(
          task: newTask('b', due: today, min: 8 * 60),
        ),
        now: now,
      );
      await tasks.save(
        TaskDraft(task: newTask('c', due: DateTime(2026, 11, 20))),
        now: now,
      );
      final moved = await tasks.rescheduleOverdueToToday(now);
      expect(moved, hasLength(2));
      final data = await tasks.listData();
      final byTitle = {for (final t in data.tasks) t.title: t};
      expect(byTitle['a']!.dueDate, today);
      expect(byTitle['b']!.dueMinutes, isNull);
      expect(byTitle['c']!.dueDate, DateTime(2026, 11, 20));
    });

    test('marcar item de checklist e progresso', () async {
      final id = await tasks.save(
        TaskDraft(
          task: newTask('x'),
          checklist: const [
            ChecklistItem(text: 'a'),
            ChecklistItem(text: 'b'),
          ],
        ),
        now: now,
      );
      final items = (await tasks.get(id))!.checklist;
      final p = await tasks.setItemChecked(items.first.id!, true);
      expect(p.label, '1/2');
      expect((await tasks.listData()).progress[id]!.label, '1/2');
    });

    test('excluir remove checklist, tags e lembretes', () async {
      final id = await tasks.save(
        TaskDraft(
          task: newTask('x', due: today),
          checklist: const [ChecklistItem(text: 'a')],
          tagNames: const ['t'],
        ),
        now: now,
      );
      await tasks.delete(id);
      expect(await db.query('checklist_item'), isEmpty);
      expect(await db.query('tarefa_tag'), isEmpty);
      expect(await db.query('lembrete'), isEmpty);
    });

    test('ordem manual', () async {
      final a = await tasks.save(TaskDraft(task: newTask('a')), now: now);
      final b = await tasks.save(TaskDraft(task: newTask('b')), now: now);
      await tasks.reorder([b, a]);
      final data = await tasks.listData();
      final order = {for (final t in data.tasks) t.id: t.order};
      expect(order[b]! < order[a]!, isTrue);
    });
  });

  group('eventos', () {
    Future<EventOccurrence> occOn(int id, DateTime day) async {
      final s = (await events.allSeries()).firstWhere((s) => s.event.id == id);
      return expandEvents([s], day, day).single;
    }

    Future<List<String>> starts(DateTime from, DateTime to) async => expandEvents(
      await events.seriesInRange(from, to),
      from,
      to,
    ).map((o) => '${toIsoDateTime(o.start)} ${o.title}').toList();

    test('evento novo ganha o lembrete padrão', () async {
      final id = await events.save(
        EventDraft(event: newEvent('Dentista', DateTime(2026, 11, 20, 14, 30), DateTime(2026, 11, 20, 15, 30))),
        now: now,
        defaultReminderMin: 15,
      );
      expect((await events.get(id))!.reminders.single.offsetMin, 15);
    });

    test('validação: fim depois do início', () {
      expect(
        () => events.save(EventDraft(event: newEvent('x', now, now)), now: now),
        throwsA(isA<ValidationException>()),
      );
    });

    test('só este, este e os seguintes, todos', () async {
      final id = await events.save(
        EventDraft(
          event: newEvent('Aula', DateTime(2026, 11, 2, 9), DateTime(2026, 11, 2, 10)),
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1]),
        ),
        now: now,
      );
      // Só este: 09/11 vira 11h.
      final o9 = await occOn(id, DateTime(2026, 11, 9));
      await events.saveOccurrence(
        EditScope.onlyThis,
        o9,
        EventDraft(
          event: o9.event.copyWith(start: DateTime(2026, 11, 9, 11), end: DateTime(2026, 11, 9, 12)),
        ),
        now: now,
      );
      expect(await starts(DateTime(2026, 11, 1), DateTime(2026, 11, 17)), [
        '2026-11-02T09:00 Aula',
        '2026-11-09T11:00 Aula',
        '2026-11-16T09:00 Aula',
      ]);

      // Excluir só 16/11.
      await events.deleteOccurrence(EditScope.onlyThis, await occOn(id, DateTime(2026, 11, 16)), now: now);
      expect(await starts(DateTime(2026, 11, 15), DateTime(2026, 11, 17)), isEmpty);

      // Este e os seguintes a partir de 23/11: novo título e 8h.
      final o23 = await occOn(id, DateTime(2026, 11, 23));
      final newId = await events.saveOccurrence(
        EditScope.thisAndFollowing,
        o23,
        EventDraft(
          event: o23.event.copyWith(
            title: 'Aula nova',
            start: DateTime(2026, 11, 23, 8),
            end: DateTime(2026, 11, 23, 9),
          ),
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1]),
        ),
        now: now,
      );
      expect(newId, isNot(id));
      final orig = (await events.get(id))!;
      expect(orig.rule!.until, DateTime(2026, 11, 22));
      expect(await starts(DateTime(2026, 11, 20), DateTime(2026, 12, 1)), [
        '2026-11-23T08:00 Aula nova',
        '2026-11-30T08:00 Aula nova',
      ]);

      // Todos (da série nova): muda o horário para 7h.
      final o30 = await occOn(newId, DateTime(2026, 11, 30));
      await events.saveOccurrence(
        EditScope.all,
        o30,
        EventDraft(
          event: o30.event.copyWith(start: DateTime(2026, 11, 30, 7), end: DateTime(2026, 11, 30, 8)),
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1]),
        ),
        now: now,
      );
      expect(await starts(DateTime(2026, 11, 20), DateTime(2026, 12, 1)), [
        '2026-11-23T07:00 Aula nova',
        '2026-11-30T07:00 Aula nova',
      ]);

      // Excluir este e os seguintes a partir de 30/11.
      await events.deleteOccurrence(EditScope.thisAndFollowing, await occOn(newId, DateTime(2026, 11, 30)), now: now);
      expect(await starts(DateTime(2026, 11, 20), DateTime(2026, 12, 31)), ['2026-11-23T07:00 Aula nova']);
    });

    test('seriesInRange só traz únicos do intervalo e todas as recorrentes', () async {
      await events.save(
        EventDraft(event: newEvent('Longe', DateTime(2026, 1, 1, 9), DateTime(2026, 1, 1, 10))),
        now: now,
      );
      await events.save(
        EventDraft(event: newEvent('Perto', DateTime(2026, 11, 17, 9), DateTime(2026, 11, 17, 10))),
        now: now,
      );
      await events.save(
        EventDraft(event: newEvent('Feriado', DateTime(2026, 11, 16), DateTime(2026, 11, 18), allDay: true)),
        now: now,
      );
      final s = await events.seriesInRange(today, today);
      expect(s.map((x) => x.event.title).toSet(), {'Perto', 'Feriado'});
    });

    test('agenda com 2.000 eventos carrega rápido', () async {
      await events.seedLoad(2000, now);
      final sw = Stopwatch()..start();
      final s = await events.seriesInRange(DateTime(2026, 11, 1), DateTime(2026, 12, 6));
      final o = expandEvents(s, DateTime(2026, 11, 1), DateTime(2026, 12, 6));
      sw.stop();
      expect(o, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(300));
    });
  });

  group('tags, categorias, modelos e filtros', () {
    test('mesclar tags', () async {
      final t = TagRepository(db);
      final a = await tasks.save(
        TaskDraft(task: newTask('a'), tagNames: const ['compra']),
        now: now,
      );
      await tasks.save(
        TaskDraft(task: newTask('b'), tagNames: const ['compras']),
        now: now,
      );
      final all = await t.all();
      await t.merge(all.firstWhere((x) => x.name == 'compra').id!, all.firstWhere((x) => x.name == 'compras').id!);
      expect((await t.all()).map((x) => x.name), ['compras']);
      expect((await tasks.get(a))!.tags.single.name, 'compras');
      expect(() => t.rename(all.firstWhere((x) => x.name == 'compras').id!, ''), throwsArgumentError);
    });

    test('categoria com nome repetido é recusada', () async {
      expect(
        () => CategoryRepository(db).save(const Category(name: 'casa', color: '#000000', icon: 'home')),
        throwsArgumentError,
      );
    });

    test('modelo salvo a partir da checklist', () async {
      final r = TemplateRepository(db);
      await r.save(
        const ChecklistTemplate(
          name: 'Farmácia',
          items: [ChecklistItem(text: 'dipirona', quantity: '1 cx')],
        ),
      );
      final all = await r.all();
      expect(all.map((t) => t.name), ['Farmácia', 'Mercado']);
      expect(all.first.items.single.quantity, '1 cx');
    });

    test('filtro salvo ida e volta', () async {
      final s = SearchRepository(db);
      await s.saveFilter('Urgentes do trabalho', const SearchCriteria(categoryIds: {1}, priorities: {1}));
      final f = (await s.savedFilters()).single;
      expect(f.name, 'Urgentes do trabalho');
      expect(f.criteria.priorities, {1});
    });

    test('busca encontra eventos e respeita filtros de tarefa', () async {
      await events.save(
        EventDraft(event: newEvent('Dentista', DateTime(2026, 11, 17, 14), DateTime(2026, 11, 17, 15))),
        now: now,
      );
      final s = SearchRepository(db);
      expect((await s.search(const SearchCriteria(text: 'dentista'), now)).events, hasLength(1));
      expect((await s.search(const SearchCriteria(text: 'dentista', priorities: {1}), now)).events, isEmpty);
    });
  });

  group('backup', () {
    test('exporta e importa substituindo tudo', () async {
      await tasks.save(
        TaskDraft(
          task: newTask('Backup', due: today),
          checklist: const [ChecklistItem(text: 'x')],
        ),
        now: now,
      );
      final b = BackupService(db);
      final json = await b.exportJson(now: now);
      expect(BackupService.fileName(now), 'trilho-backup-2026-11-17.json');

      await tasks.save(TaskDraft(task: newTask('Depois do backup')), now: now);
      final data = b.decode(json);
      final summary = b.validate(data);
      expect(summary.tasks, 1);
      await b.importData(data);
      final titles = (await tasks.listData()).tasks.map((t) => t.title);
      expect(titles, ['Backup']);
      expect(await db.query('checklist_item'), hasLength(1));
    });

    test('recusa backup de outro app ou de versão mais nova', () {
      final b = BackupService(db);
      expect(() => b.validate({'app': 'lastro'}), throwsA(isA<BackupException>()));
      expect(() => b.validate({'app': 'trilho', 'schema_version': 99, 'tabelas': {}}), throwsA(isA<BackupException>()));
      expect(() => b.decode('{'), throwsA(isA<BackupException>()));
    });
  });

  group('ações da notificação (sem abrir o app)', () {
    test('Concluir e Adiar 1h', () async {
      final a = await tasks.save(
        TaskDraft(
          task: newTask('A', due: today, min: 11 * 60),
        ),
        now: now,
      );
      final b = await tasks.save(
        TaskDraft(
          task: newTask('B', due: today, min: 11 * 60),
        ),
        now: now,
      );
      final m1 = await applyNotificationAction(db, actionComplete, 'tarefa:$a', now);
      expect(m1!.$1, 'Concluída ✔');
      expect((await tasks.get(a))!.task.isDone, isTrue);
      final m2 = await applyNotificationAction(db, actionSnooze, 'tarefa:$b', now);
      expect(m2!.$1, 'Adiada para 11:00');
      final tb = (await tasks.get(b))!.task;
      expect(tb.dueMinutes, 11 * 60);
      expect(tb.postponements, 0); // 10h+1h = 11h, igual ao prazo: não empurrou para frente
      expect(await applyNotificationAction(db, actionComplete, 'tarefa:$a', now), isNull); // já concluída
      expect(await applyNotificationAction(db, actionComplete, 'hoje', now), isNull);
    });
  });

  test('PIN com hash e salt', () async {
    final store = MemoryPinStore();
    final pin = PinService(store);
    expect(PinService.validate('12'), isNotNull);
    expect(PinService.validate('1234'), isNull);
    await pin.setPin('2468');
    expect(store.data.values, isNot(contains('2468')));
    expect(await pin.check('2468'), isTrue);
    expect(await pin.check('1357'), isFalse);
    await pin.clear();
    expect(await pin.hasPin(), isFalse);
  });
}
