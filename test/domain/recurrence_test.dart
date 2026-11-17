import 'package:flutter_test/flutter_test.dart';
import 'package:trilho/domain/dates.dart';
import 'package:trilho/domain/event_expansion.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/domain/recurrence.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);
List<String> iso(List<DateTime> l) => l.map(toIsoDate).toList();

Event ev(DateTime start, DateTime end, {int id = 1, bool allDay = false, int? rid}) => Event(
      id: id,
      title: 'Evento $id',
      start: start,
      end: end,
      allDay: allDay,
      recurrenceId: rid,
      createdAt: start,
      updatedAt: start,
    );

void main() {
  group('expansão de recorrência', () {
    test('sem regra: só a data de início, se estiver no intervalo', () {
      expect(iso(occurrencesBetween(null, d(2026, 3, 5), d(2026, 3, 1), d(2026, 3, 31))), ['2026-03-05']);
      expect(occurrencesBetween(null, d(2026, 3, 5), d(2026, 4, 1), d(2026, 4, 30)), isEmpty);
    });

    test('diária a cada 2 dias', () {
      const r = RecurrenceRule(freq: Freq.diaria, interval: 2);
      expect(iso(occurrencesBetween(r, d(2026, 1, 1), d(2026, 1, 1), d(2026, 1, 9))),
          ['2026-01-01', '2026-01-03', '2026-01-05', '2026-01-07', '2026-01-09']);
    });

    test('diária pulando para longe no futuro continua alinhada', () {
      const r = RecurrenceRule(freq: Freq.diaria, interval: 3);
      final occ = occurrencesBetween(r, d(2020, 1, 1), d(2026, 6, 1), d(2026, 6, 10));
      for (final o in occ) {
        expect(daysBetween(d(2020, 1, 1), o) % 3, 0);
      }
      expect(occ.length, inInclusiveRange(3, 4));
    });

    test('semanal com vários dias (seg, qua, sex)', () {
      const r = RecurrenceRule(freq: Freq.semanal, weekdays: [1, 3, 5]);
      // 02/03/2026 é segunda.
      expect(iso(occurrencesBetween(r, d(2026, 3, 2), d(2026, 3, 1), d(2026, 3, 10))),
          ['2026-03-02', '2026-03-04', '2026-03-06', '2026-03-09']);
    });

    test('semanal a cada 2 semanas, seg e qua', () {
      const r = RecurrenceRule(freq: Freq.semanal, interval: 2, weekdays: [1, 3]);
      expect(iso(occurrencesBetween(r, d(2026, 3, 2), d(2026, 3, 1), d(2026, 3, 31))),
          ['2026-03-02', '2026-03-04', '2026-03-16', '2026-03-18', '2026-03-30']);
    });

    test('semanal não gera dias antes do início na primeira semana', () {
      const r = RecurrenceRule(freq: Freq.semanal, weekdays: [1, 5]);
      // Início numa quarta: a segunda dessa semana não entra.
      expect(iso(occurrencesBetween(r, d(2026, 3, 4), d(2026, 3, 1), d(2026, 3, 10))),
          ['2026-03-06', '2026-03-09']);
    });

    test('mensal por dia do mês', () {
      const r = RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDoMes);
      expect(iso(occurrencesBetween(r, d(2026, 1, 10), d(2026, 1, 1), d(2026, 4, 30))),
          ['2026-01-10', '2026-02-10', '2026-03-10', '2026-04-10']);
    });

    test('mensal no dia 31 pula os meses curtos', () {
      const r = RecurrenceRule(freq: Freq.mensal);
      expect(iso(occurrencesBetween(r, d(2026, 1, 31), d(2026, 1, 1), d(2026, 7, 31))),
          ['2026-01-31', '2026-03-31', '2026-05-31', '2026-07-31']);
    });

    test('mensal por dia da semana: toda 2ª terça', () {
      const r = RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDaSemana);
      // 10/03/2026 é a 2ª terça de março.
      expect(iso(occurrencesBetween(r, d(2026, 3, 10), d(2026, 3, 1), d(2026, 6, 30))),
          ['2026-03-10', '2026-04-14', '2026-05-12', '2026-06-09']);
    });

    test('mensal na 5ª segunda pula meses sem 5ª segunda', () {
      const r = RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDaSemana);
      // 30/03/2026 é a 5ª segunda de março; abril e maio não têm 5ª segunda... junho tem 29/06.
      final occ = iso(occurrencesBetween(r, d(2026, 3, 30), d(2026, 3, 1), d(2026, 8, 31)));
      expect(occ.first, '2026-03-30');
      expect(occ, contains('2026-06-29'));
      expect(occ, isNot(contains(startsWith('2026-04'))));
    });

    test('anual', () {
      const r = RecurrenceRule(freq: Freq.anual);
      expect(iso(occurrencesBetween(r, d(2026, 5, 20), d(2026, 1, 1), d(2028, 12, 31))),
          ['2026-05-20', '2027-05-20', '2028-05-20']);
    });

    test('29/02 só nos anos bissextos', () {
      const r = RecurrenceRule(freq: Freq.anual);
      expect(iso(occurrencesBetween(r, d(2024, 2, 29), d(2024, 1, 1), d(2032, 12, 31))),
          ['2024-02-29', '2028-02-29', '2032-02-29']);
    });

    test('ate encerra a série (inclusivo)', () {
      final r = RecurrenceRule(freq: Freq.diaria, until: d(2026, 1, 3));
      expect(iso(occurrencesBetween(r, d(2026, 1, 1), d(2026, 1, 1), d(2026, 1, 31))),
          ['2026-01-01', '2026-01-02', '2026-01-03']);
    });

    test('contagem limita o número de ocorrências', () {
      const r = RecurrenceRule(freq: Freq.semanal, weekdays: [2, 4], count: 3);
      expect(iso(occurrencesBetween(r, d(2026, 3, 3), d(2026, 1, 1), d(2026, 12, 31))),
          ['2026-03-03', '2026-03-05', '2026-03-10']);
    });

    test('contagem é contada desde o início, mesmo consultando depois', () {
      const r = RecurrenceRule(freq: Freq.diaria, count: 5);
      expect(iso(occurrencesBetween(r, d(2026, 1, 1), d(2026, 1, 4), d(2026, 1, 31))),
          ['2026-01-04', '2026-01-05']);
    });

    test('próxima ocorrência e ocorrências anteriores', () {
      const r = RecurrenceRule(freq: Freq.semanal, weekdays: [1]);
      expect(nextOccurrenceAfter(r, d(2026, 3, 2), d(2026, 3, 2)), d(2026, 3, 9));
      expect(occurrencesBefore(r, d(2026, 3, 2), d(2026, 3, 23)), 3);
      const c = RecurrenceRule(freq: Freq.diaria, count: 2);
      expect(nextOccurrenceAfter(c, d(2026, 1, 1), d(2026, 1, 2)), isNull);
    });

    test('descrição amigável', () {
      final r = RecurrenceRule(freq: Freq.semanal, interval: 2, weekdays: const [1, 3], until: d(2026, 6, 30));
      expect(describeRecurrence(r, d(2026, 3, 2)), 'A cada 2 semanas, seg e qua, até 30/06');
      expect(describeRecurrence(const RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDaSemana), d(2026, 3, 10)),
          'Todo mês, na 2ª terça');
      expect(describeRecurrence(const RecurrenceRule(freq: Freq.diaria, count: 3), d(2026, 1, 1)), 'Todo dia, 3 vezes');
      expect(describeRecurrence(const RecurrenceRule(freq: Freq.mensal), d(2026, 1, 10)), 'Todo mês, no dia 10');
    });
  });

  group('expansão de eventos', () {
    test('evento único com hora', () {
      final s = EventSeries(ev(DateTime(2026, 3, 5, 14, 30), DateTime(2026, 3, 5, 15, 30)));
      final o = expandEvents([s], d(2026, 3, 1), d(2026, 3, 31));
      expect(o, hasLength(1));
      expect(o.first.start, DateTime(2026, 3, 5, 14, 30));
      expect(o.first.end, DateTime(2026, 3, 5, 15, 30));
    });

    test('recorrente semanal mantém horário e duração', () {
      final s = EventSeries(ev(DateTime(2026, 3, 2, 9), DateTime(2026, 3, 2, 10), rid: 1),
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1]));
      final o = expandEvents([s], d(2026, 3, 1), d(2026, 3, 31));
      expect(o.map((x) => toIsoDateTime(x.start)), ['2026-03-02T09:00', '2026-03-09T09:00', '2026-03-16T09:00', '2026-03-23T09:00', '2026-03-30T09:00']);
      expect(o.every((x) => x.end.difference(x.start) == const Duration(hours: 1)), isTrue);
    });

    test('exceções cancelam e alteram ocorrências', () {
      final s = EventSeries(
        ev(DateTime(2026, 3, 2, 9), DateTime(2026, 3, 2, 10), rid: 1),
        rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1]),
        exceptions: [
          EventException(eventId: 1, occurrenceDate: d(2026, 3, 9), cancelled: true),
          EventException(
              eventId: 1,
              occurrenceDate: d(2026, 3, 16),
              newStart: DateTime(2026, 3, 17, 11),
              newEnd: DateTime(2026, 3, 17, 12),
              newTitle: 'Remarcado'),
        ],
      );
      final o = expandEvents([s], d(2026, 3, 1), d(2026, 3, 20));
      expect(o.map((x) => toIsoDateTime(x.start)), ['2026-03-02T09:00', '2026-03-17T11:00']);
      expect(o.last.title, 'Remarcado');
      expect(o.last.modified, isTrue);
      expect(o.last.occurrenceDate, d(2026, 3, 16));
    });

    test('evento de vários dias que começou antes aparece no intervalo', () {
      final s = EventSeries(ev(d(2026, 2, 27), d(2026, 3, 2), allDay: true));
      final o = expandEvents([s], d(2026, 3, 1), d(2026, 3, 31));
      expect(o, hasLength(1));
      expect(o.first.occursOn(d(2026, 3, 2)), isTrue);
      expect(o.first.occursOn(d(2026, 3, 3)), isFalse);
    });

    test('desempenho: 2.000 eventos expandem rápido', () {
      final series = [
        for (var i = 0; i < 2000; i++)
          EventSeries(
            ev(DateTime(2026, 1, 1 + i % 300, 8 + i % 10), DateTime(2026, 1, 1 + i % 300, 9 + i % 10), id: i, rid: i % 10 == 0 ? i : null),
            rule: i % 10 == 0 ? const RecurrenceRule(freq: Freq.semanal) : null,
          ),
      ];
      final sw = Stopwatch()..start();
      final o = expandEvents(series, d(2026, 6, 1), d(2026, 7, 12));
      sw.stop();
      expect(o, isNotEmpty);
      expect(sw.elapsedMilliseconds, lessThan(300));
    });
  });
}
