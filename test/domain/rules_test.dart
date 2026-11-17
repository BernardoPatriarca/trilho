import 'package:flutter_test/flutter_test.dart';
import 'package:trilho/domain/daily_summary.dart';
import 'package:trilho/domain/dates.dart';
import 'package:trilho/domain/event_expansion.dart';
import 'package:trilho/domain/ics.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/domain/search.dart';
import 'package:trilho/domain/stats.dart';
import 'package:trilho/domain/tasks.dart';
import 'package:trilho/domain/text.dart';
import 'package:trilho/domain/today.dart';

final now = DateTime(2026, 11, 17, 10); // terça, 10:00
final today = DateTime(2026, 11, 17);

var _id = 0;
Task task(String title,
    {DateTime? due,
    int? min,
    int priority = 4,
    TaskStatus status = TaskStatus.pendente,
    DateTime? completedAt,
    DateTime? createdAt,
    bool pinned = false,
    int? cat,
    int order = 0,
    int postponements = 0,
    int? rid}) {
  final c = createdAt ?? DateTime(2026, 11, 1, 8);
  return Task(
    id: ++_id,
    title: title,
    dueDate: due,
    dueMinutes: min,
    priority: priority,
    status: status,
    completedAt: completedAt,
    createdAt: c,
    updatedAt: completedAt ?? c,
    pinnedToday: pinned,
    categoryId: cat,
    order: order,
    postponements: postponements,
    recurrenceId: rid,
  );
}

EventOccurrence occ(String title, DateTime start, DateTime end, {bool allDay = false, int? cat, String? local}) {
  final e = Event(
      id: ++_id, title: title, start: start, end: end, allDay: allDay, categoryId: cat, location: local, createdAt: start, updatedAt: start);
  return EventOccurrence(event: e, start: start, end: end, occurrenceDate: dateOnly(start), title: title);
}

void main() {
  group('atrasadas', () {
    test('prazo antes de hoje', () => expect(isOverdue(task('a', due: DateTime(2026, 11, 16)), now), isTrue));
    test('hoje sem hora não é atrasada', () => expect(isOverdue(task('a', due: today), now), isFalse));
    test('hoje com hora passada é atrasada', () => expect(isOverdue(task('a', due: today, min: 9 * 60), now), isTrue));
    test('hoje com hora futura não é atrasada', () => expect(isOverdue(task('a', due: today, min: 11 * 60), now), isFalse));
    test('concluída nunca é atrasada',
        () => expect(isOverdue(task('a', due: DateTime(2026, 1, 1), status: TaskStatus.concluida), now), isFalse));
    test('sem prazo não é atrasada', () => expect(isOverdue(task('a'), now), isFalse));
  });

  group('tarefa recorrente', () {
    test('próximo prazo vem do prazo original, não da conclusão', () {
      final t = task('Mercado', due: DateTime(2026, 11, 9)); // segunda passada
      const rule = RecurrenceRule(freq: Freq.semanal, weekdays: [1]);
      expect(nextDueDate(t, rule), DateTime(2026, 11, 16));
    });
    test('contagem: última instância não gera próxima', () {
      final t = task('x', due: today);
      expect(nextDueDate(t, const RecurrenceRule(freq: Freq.diaria, count: 1)), isNull);
      expect(nextInstanceRule(const RecurrenceRule(freq: Freq.diaria, count: 3)).count, 2);
    });
    test('checklist copiada vem toda desmarcada e na ordem', () {
      final items = [
        const ChecklistItem(id: 1, text: 'óleo', quantity: '1', checked: true, order: 3),
        const ChecklistItem(id: 2, text: 'açúcar', checked: true, order: 1),
        const ChecklistItem(id: 3, text: 'arroz', order: 2),
      ];
      final r = resetChecklist(items);
      expect(r.every((i) => !i.checked && i.id == null), isTrue);
      expect(r.map((i) => i.text), ['óleo', 'açúcar', 'arroz']);
      expect(r.first.quantity, '1');
    });
    test('próxima instância herda dados e zera status', () {
      final t = task('Mercado', due: DateTime(2026, 11, 9), min: 18 * 60, priority: 2, cat: 7, postponements: 3);
      final n = nextInstance(t, DateTime(2026, 11, 16), now, 99);
      expect(n.id, isNull);
      expect(n.dueDate, DateTime(2026, 11, 16));
      expect(n.dueMinutes, 18 * 60);
      expect(n.priority, 2);
      expect(n.categoryId, 7);
      expect(n.status, TaskStatus.pendente);
      expect(n.postponements, 0);
      expect(n.recurrenceId, 99);
    });
    test('lembretes absolutos andam com o prazo', () {
      final r = shiftReminders([const Reminder.relative(30), Reminder.absolute(DateTime(2026, 11, 8, 20))],
          DateTime(2026, 11, 9), DateTime(2026, 11, 16));
      expect(r[0].offsetMin, 30);
      expect(r[1].at, DateTime(2026, 11, 15, 20));
    });
  });

  group('adiar', () {
    test('mover para frente incrementa adiamentos', () {
      final t = task('a', due: today, min: 9 * 60);
      final p = postpone(t, today, 19 * 60, now);
      expect(p.postponements, 1);
      expect(p.dueMinutes, 19 * 60);
    });
    test('mover para trás não incrementa', () {
      final t = task('a', due: DateTime(2026, 11, 20));
      expect(postpone(t, DateTime(2026, 11, 18), null, now).postponements, 0);
    });
    test('atalhos', () {
      final opts = postponeOptions(task('a', due: today, min: 9 * 60), now);
      expect(opts.map((o) => o.label), ['+1 hora', 'Hoje à noite (19h)', 'Amanhã', 'Próxima segunda']);
      expect(opts[0].minutes, 11 * 60);
      expect(opts[2].date, DateTime(2026, 11, 18));
      expect(opts[2].minutes, 9 * 60);
      expect(opts[3].date, DateTime(2026, 11, 23));
    });
    test('depois das 19h não oferece "hoje à noite"', () {
      final opts = postponeOptions(task('a'), DateTime(2026, 11, 17, 20));
      expect(opts.map((o) => o.label), isNot(contains('Hoje à noite (19h)')));
    });
  });

  group('validações', () {
    test('título obrigatório', () => expect(validateTask(title: '  '), 'Informe o título da tarefa.'));
    test('hora só com data', () => expect(validateTask(title: 'a', dueMinutes: 60), 'A hora do prazo precisa de uma data.'));
    test('fim depois do início', () {
      expect(validateEvent(title: 'a', start: now, end: now, allDay: false), 'O fim precisa ser depois do início.');
      expect(validateEvent(title: 'a', start: today, end: today, allDay: true), isNull);
    });
  });

  group('tela Hoje', () {
    test('monta as seções na ordem e com as regras', () {
      final atrasada = task('Atrasada', due: DateTime(2026, 11, 15));
      final passouHoje = task('Passou hoje', due: today, min: 8 * 60);
      final comHora = task('Com hora', due: today, min: 15 * 60);
      final p4 = task('Sem hora P4', due: today, priority: 4);
      final p1 = task('Sem hora P1', due: today, priority: 1);
      final fixada = task('Fixada', due: DateTime(2026, 11, 30), pinned: true);
      final feita = task('Feita', due: today, status: TaskStatus.concluida, completedAt: DateTime(2026, 11, 17, 9));
      final feitaOntem = task('Ontem', status: TaskStatus.concluida, completedAt: DateTime(2026, 11, 16, 9));
      final futura = task('Futura', due: DateTime(2026, 11, 25));
      final view = buildToday(
        tasks: [atrasada, passouHoje, comHora, p4, p1, fixada, feita, feitaOntem, futura],
        events: [
          occ('Reunião', DateTime(2026, 11, 17, 14), DateTime(2026, 11, 17, 15)),
          occ('Feriado', today, today, allDay: true),
          occ('Amanhã', DateTime(2026, 11, 18, 9), DateTime(2026, 11, 18, 10)),
        ],
        now: now,
      );
      expect(view.overdue.map((t) => t.title), ['Atrasada', 'Passou hoje']);
      expect(view.allDayEvents.map((e) => e.title), ['Feriado']);
      expect(view.timeline.map((e) => e.event?.title ?? e.task!.title), ['Reunião', 'Com hora']);
      expect(view.untimed.map((t) => t.title), ['Sem hora P1', 'Sem hora P4']);
      expect(view.pinned.map((t) => t.title), ['Fixada']);
      expect(view.completedToday.map((t) => t.title), ['Feita']);
      expect(view.doneCount, 1);
      expect(view.totalCount, 7);
      expect(view.eventCount, 2);
    });

    test('dia vazio', () {
      final v = buildToday(tasks: [task('futura', due: DateTime(2026, 12, 1))], events: const [], now: now);
      expect(v.isEmpty, isTrue);
    });
  });

  group('busca', () {
    test('normalização sem acento e minúscula, mesmo tamanho', () {
      expect(normalizeText('Óleo de SOJA, Açúcar'), 'oleo de soja, acucar');
      expect(normalizeText('Ação').length, 'Ação'.length);
    });
    test('índice inclui itens da checklist', () {
      final idx = searchIndex(['Ir ao mercado', null, 'óleo', 'açúcar']);
      expect(matchesSearch(idx, 'oleo'), isTrue);
      expect(matchesSearch(idx, 'ÓLEO mercado'), isTrue);
      expect(matchesSearch(idx, 'feijão'), isFalse);
    });
    test('destaque do termo no texto original', () {
      expect(highlightRanges('Comprar Óleo e óleo', 'oleo'), [(8, 12), (15, 19)]);
    });
    test('colar lista: linhas ou vírgulas', () {
      expect(splitPastedList('- arroz\n- feijão\n\n• óleo'), ['arroz', 'feijão', 'óleo']);
      expect(splitPastedList('arroz, feijão; óleo'), ['arroz', 'feijão', 'óleo']);
      expect(splitPastedList('[ ] leite\n1. ovos'), ['leite', 'ovos']);
    });

    final t1 = TaskSearchRow(
        task: task('Ir ao mercado', due: today, priority: 2, cat: 7), index: searchIndex(['Ir ao mercado', 'óleo']), tagIds: {1}, checklistCount: 2);
    final t2 = TaskSearchRow(task: task('Relatório', due: DateTime(2026, 11, 10), priority: 1, cat: 1), index: 'relatorio');
    final t3 = TaskSearchRow(task: task('Sem prazo', priority: 4, rid: 3), index: 'sem prazo');

    List<String> run(SearchCriteria c) =>
        [t1, t2, t3].where((r) => taskMatches(r, c, now)).map((r) => r.task.title).toList();

    test('texto', () => expect(run(const SearchCriteria(text: 'óleo')), ['Ir ao mercado']));
    test('categoria + prioridade combinadas', () {
      expect(run(const SearchCriteria(categoryIds: {1, 7}, priorities: {1})), ['Relatório']);
    });
    test('tag', () => expect(run(const SearchCriteria(tagIds: {1})), ['Ir ao mercado']));
    test('com e sem prazo', () {
      expect(run(const SearchCriteria(withDue: false)), ['Sem prazo']);
      expect(run(const SearchCriteria(withDue: true)), ['Ir ao mercado', 'Relatório']);
    });
    test('só atrasadas', () => expect(run(const SearchCriteria(onlyOverdue: true)), ['Relatório']));
    test('com checklist', () => expect(run(const SearchCriteria(withChecklist: true)), ['Ir ao mercado']));
    test('recorrentes', () => expect(run(const SearchCriteria(onlyRecurring: true)), ['Sem prazo']));
    test('período: hoje e esta semana', () {
      expect(run(const SearchCriteria(period: SearchPeriod.hoje)), ['Ir ao mercado']);
      expect(run(const SearchCriteria(period: SearchPeriod.mes)), ['Ir ao mercado', 'Relatório']);
    });
    test('tipo evento exclui tarefas', () => expect(run(const SearchCriteria(includeTasks: false)), isEmpty));
    test('critérios ida e volta em JSON', () {
      final c = SearchCriteria(
          text: 'x', categoryIds: const {2}, priorities: const {1, 2}, statuses: const {TaskStatus.pendente}, period: SearchPeriod.personalizado, from: today, to: today, withDue: true);
      final back = SearchCriteria.decode(c.encode());
      expect(back.encode(), c.encode());
      expect(back.activeFilters, 5);
    });
    test('evento casa por texto e período', () {
      final e = occ('Dentista', DateTime(2026, 11, 17, 14), DateTime(2026, 11, 17, 15)).event;
      final row = EventSearchRow(event: e, index: 'dentista', occurrenceDates: [today]);
      expect(eventMatches(row, const SearchCriteria(text: 'dent', period: SearchPeriod.hoje), now), isTrue);
      expect(eventMatches(row, const SearchCriteria(priorities: {1}), now), isFalse);
      expect(eventMatches(EventSearchRow(event: e, index: 'dentista'), const SearchCriteria(period: SearchPeriod.hoje), now), isFalse);
    });
  });

  group('estatísticas', () {
    final tasks = [
      // Esta semana: 3 concluídas (2 no prazo de 3 com prazo).
      task('a', due: DateTime(2026, 11, 17), status: TaskStatus.concluida, completedAt: DateTime(2026, 11, 17, 9), cat: 1, createdAt: DateTime(2026, 11, 16, 9)),
      task('b', due: DateTime(2026, 11, 15), status: TaskStatus.concluida, completedAt: DateTime(2026, 11, 16, 14), cat: 1, createdAt: DateTime(2026, 11, 14, 14)),
      task('c', due: DateTime(2026, 11, 16), min: 12 * 60, status: TaskStatus.concluida, completedAt: DateTime(2026, 11, 16, 11), cat: 2, createdAt: DateTime(2026, 11, 16, 9)),
      // Semana anterior: 1.
      task('d', status: TaskStatus.concluida, completedAt: DateTime(2026, 11, 8, 9)),
      // Pendentes.
      task('e', due: DateTime(2026, 11, 10), postponements: 2, createdAt: DateTime(2026, 11, 12)),
      task('f', createdAt: DateTime(2026, 11, 13)),
    ];
    final s = computeStats(tasks: tasks, events: [
      occ('Aula', DateTime(2026, 11, 16, 8), DateTime(2026, 11, 16, 10), cat: 2),
      occ('Aula', DateTime(2026, 11, 17, 8), DateTime(2026, 11, 17, 9, 30), cat: 2),
    ], now: now, period: StatsPeriod.d7);

    test('concluídas por dia e comparação', () {
      expect(s.perDay, hasLength(7));
      expect(s.perDay.last.count, 1);
      expect(s.perDay[5].count, 2);
      expect(s.total, 3);
      expect(s.previousTotal, 1);
      expect(comparisonText(s.total, s.previousTotal, StatsPeriod.d7), '3 concluídas, 2 a mais que nos 7 dias anteriores');
      expect(comparisonText(2, 2, StatsPeriod.d7), '2 concluídas, o mesmo número que nos 7 dias anteriores');
      expect(comparisonText(1, 4, StatsPeriod.d30), '1 concluída, 3 a menos que nos 30 dias anteriores');
    });
    test('taxa no prazo', () {
      expect(s.withDueCount, 3);
      expect(s.onTimeCount, 2);
      expect(s.onTimeRate, closeTo(2 / 3, 1e-9));
    });
    test('atrasadas e média de adiamentos', () {
      expect(s.overdueNow, 1);
      // Criadas no período: a, b, c, e, f → adiamentos 0,0,0,2,0.
      expect(s.avgPostponements, closeTo(0.4, 1e-9));
    });
    test('por categoria e tempo de eventos', () {
      expect(s.completedByCategory, {1: 2, 2: 1});
      expect(s.eventMinutesByCategory, {2: 210});
    });
    test('sequência', () => expect(s.streak, 2));
    test('mapa de calor', () {
      expect(s.heatmap[1][9], 1); // terça 9h
      expect(s.heatmap[0][14], 1); // segunda 14h
      expect(s.heatmap[0][11], 1);
    });
    test('tempo médio entre criar e concluir', () {
      // a: 24h, b: 48h, c: 2h → média 24h40.
      expect(s.avgLeadTime, const Duration(hours: 24, minutes: 40));
      expect(formatDuration(const Duration(hours: 24, minutes: 40)), '24 h 40 min');
    });
    test('revisão semanal', () {
      expect(s.review.completed, 3);
      expect(s.review.created, 5);
      expect(s.review.postponed, 1);
      expect(s.review.topCategoryId, 1);
    });
    test('sequência sem conclusão hoje conta até ontem', () {
      final st = computeStats(tasks: tasks.sublist(1), events: const [], now: now, period: StatsPeriod.d30);
      expect(st.streak, 1);
    });
    test('"Tudo" longo agrupa por mês', () {
      final st = computeStats(tasks: [
        task('velha', status: TaskStatus.concluida, completedAt: DateTime(2026, 1, 5), createdAt: DateTime(2026, 1, 1)),
        ...tasks,
      ], events: const [], now: now, period: StatsPeriod.all);
      expect(st.groupedByMonth, isTrue);
      expect(st.perDay.first.day, DateTime(2026, 1));
      expect(st.previousTotal, isNull);
    });
  });

  group('resumo diário', () {
    test('dia cheio', () {
      final mercado = task('Ir ao mercado', due: today, priority: 2);
      final s = buildDailySummary(
        day: today,
        tasks: [
          task('Entregar relatório do TCC', due: today, priority: 1),
          mercado,
          task('Lavar roupa', due: today, priority: 4),
          task('Ligar', due: today, priority: 3),
          task('Velha 1', due: DateTime(2026, 11, 10)),
          task('Velha 2', due: DateTime(2026, 11, 12)),
        ],
        events: [
          occ('Dentista', DateTime(2026, 11, 17, 14, 30), DateTime(2026, 11, 17, 15, 30)),
          occ('Reunião de alinhamento', DateTime(2026, 11, 17, 9), DateTime(2026, 11, 17, 10)),
        ],
        checklist: {mercado.id!: const ChecklistProgress(0, 12)},
      );
      expect(s.title, 'Bom dia! Hoje: 4 tarefas e 2 eventos');
      expect(s.lines, [
        '09:00 · Reunião de alinhamento',
        '14:30 · Dentista',
        'P1 · Entregar relatório do TCC',
        'P2 · Ir ao mercado (0/12 itens)',
        '⚠ 2 tarefas atrasadas',
      ]);
    });

    test('dia vazio', () {
      final s = buildDailySummary(day: today, tasks: const [], events: const []);
      expect(s.title, 'Bom dia!');
      expect(s.body, 'Dia livre na agenda. Que tal adiantar algo da semana?');
    });

    test('muitas tarefas truncadas em 6 linhas', () {
      final s = buildDailySummary(
        day: today,
        tasks: [for (var i = 0; i < 10; i++) task('Urgente $i', due: today, priority: 1), task('Velha', due: DateTime(2026, 11, 1))],
        events: [occ('Evento', DateTime(2026, 11, 17, 8), DateTime(2026, 11, 17, 9))],
      );
      expect(s.lines, hasLength(6));
      expect(s.lines.first, '08:00 · Evento');
      expect(s.lines[4], '+ 7 mais');
      expect(s.lines.last, '⚠ 1 tarefa atrasada');
      expect(s.title, 'Bom dia! Hoje: 10 tarefas e 1 evento');
    });
  });

  group('ics', () {
    test('evento recorrente com RRULE, EXDATE e RECURRENCE-ID', () {
      final e = Event(
          id: 5,
          title: 'Aula, turma A',
          start: DateTime(2026, 3, 2, 9),
          end: DateTime(2026, 3, 2, 10),
          recurrenceId: 1,
          createdAt: now,
          updatedAt: now);
      final ics = exportIcs([
        EventSeries(e,
            rule: RecurrenceRule(freq: Freq.semanal, interval: 2, weekdays: const [1, 3], until: DateTime(2026, 6, 30)),
            exceptions: [
              EventException(eventId: 5, occurrenceDate: DateTime(2026, 3, 4), cancelled: true),
              EventException(eventId: 5, occurrenceDate: DateTime(2026, 3, 16), newTitle: 'Aula extra'),
            ]),
        EventSeries(Event(id: 6, title: 'Feriado', start: DateTime(2026, 4, 21), end: DateTime(2026, 4, 21), allDay: true, createdAt: now, updatedAt: now)),
      ], now: now);
      expect(ics, contains('RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE;UNTIL=20260630T235959'));
      expect(ics, contains('SUMMARY:Aula\\, turma A'));
      expect(ics, contains('EXDATE;TZID=America/Sao_Paulo:20260304T090000'));
      expect(ics, contains('RECURRENCE-ID;TZID=America/Sao_Paulo:20260316T090000'));
      expect(ics, contains('DTSTART;VALUE=DATE:20260421'));
      expect(ics, contains('DTEND;VALUE=DATE:20260422'));
      expect(ics.split('\r\n').where((l) => l == 'BEGIN:VEVENT'), hasLength(3));
    });
    test('mensal por dia da semana', () {
      expect(rruleOf(const RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDaSemana), DateTime(2026, 3, 10)),
          'RRULE:FREQ=MONTHLY;BYDAY=2TU');
      expect(rruleOf(const RecurrenceRule(freq: Freq.mensal, count: 5), DateTime(2026, 3, 10)), 'RRULE:FREQ=MONTHLY;BYMONTHDAY=10;COUNT=5');
    });
  });
}
