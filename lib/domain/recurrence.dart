// Recorrência: expansão sob demanda das ocorrências (nada é gravado por
// ocorrência) e descrição amigável da regra.
//
// Casos de borda:
// - mensal "dia 31" pula os meses sem dia 31;
// - anual em 29/02 pula os anos não bissextos;
// - mensal "dia da semana" usa a N-ésima semana do dia de início
//   (ex.: 2ª terça); se o mês não tiver a 5ª ocorrência, pula o mês.
import 'dates.dart';
import 'models.dart';

/// Ocorrências (datas, à meia-noite) da série que começa em [start], dentro
/// de [from]..[to] (inclusivo). Sem regra, a única ocorrência é [start].
List<DateTime> occurrencesBetween(
  RecurrenceRule? rule,
  DateTime start,
  DateTime from,
  DateTime to,
) {
  final s = dateOnly(start);
  final f = dateOnly(from);
  final t = dateOnly(to);
  if (rule == null) {
    return (!s.isBefore(f) && !s.isAfter(t)) ? [s] : const [];
  }
  final out = <DateTime>[];
  for (final d in _iterate(rule, s, skipTo: rule.count == null ? f : null)) {
    if (d.isAfter(t)) break;
    if (!d.isBefore(f)) out.add(d);
  }
  return out;
}

/// Primeira ocorrência estritamente depois de [after] (ou null se a série
/// acabou). Usado pela próxima instância de tarefa recorrente.
DateTime? nextOccurrenceAfter(RecurrenceRule rule, DateTime start, DateTime after) {
  final a = dateOnly(after);
  for (final d in _iterate(rule, dateOnly(start), skipTo: rule.count == null ? a : null)) {
    if (d.isAfter(a)) return d;
  }
  return null;
}

/// Quantas ocorrências da série vêm antes de [date] (para "este e os seguintes"
/// com contagem).
int occurrencesBefore(RecurrenceRule rule, DateTime start, DateTime date) {
  final d = dateOnly(date);
  var n = 0;
  for (final o in _iterate(rule, dateOnly(start))) {
    if (!o.isBefore(d)) break;
    n++;
  }
  return n;
}

/// Gera as ocorrências em ordem, respeitando `ate` e `contagem`. Com
/// [skipTo] (só sem contagem), pula direto para perto dessa data.
Iterable<DateTime> _iterate(RecurrenceRule rule, DateTime start, {DateTime? skipTo}) sync* {
  final interval = rule.interval < 1 ? 1 : rule.interval;
  final until = rule.until == null ? null : dateOnly(rule.until!);
  final count = rule.count;
  var emitted = 0;

  // Primeiro período a examinar.
  var period = 0;
  if (skipTo != null && skipTo.isAfter(start)) {
    final elapsed = switch (rule.freq) {
      Freq.diaria => daysBetween(start, skipTo),
      Freq.semanal => daysBetween(startOfWeek(start), skipTo) ~/ 7,
      Freq.mensal => (skipTo.year - start.year) * 12 + skipTo.month - start.month,
      Freq.anual => skipTo.year - start.year,
    };
    period = (elapsed ~/ interval) - 1;
    if (period < 0) period = 0;
  }

  // Limite de segurança: séries sem fim nunca passam de 400 anos à frente.
  final hardStop = DateTime(start.year + 400);
  var misses = 0;

  while (true) {
    final candidates = _period(rule, start, period * interval);
    var any = false;
    for (final d in candidates) {
      if (d.isBefore(start)) continue;
      if (until != null && d.isAfter(until)) return;
      if (d.isAfter(hardStop)) return;
      any = true;
      yield d;
      emitted++;
      if (count != null && emitted >= count) return;
    }
    // Passou do `ate` sem achar mais nada? Para.
    final periodStart = _periodStart(rule, start, period * interval);
    if (until != null && periodStart.isAfter(until)) return;
    if (periodStart.isAfter(hardStop)) return;
    misses = any ? 0 : misses + 1;
    // Regra impossível (ex.: dia 31 a cada 12 meses começando em abril):
    // depois de muitos períodos vazios, desiste.
    if (misses > 1000) return;
    period++;
  }
}

DateTime _periodStart(RecurrenceRule rule, DateTime start, int offset) => switch (rule.freq) {
      Freq.diaria => addDays(start, offset),
      Freq.semanal => addDays(startOfWeek(start), offset * 7),
      Freq.mensal => DateTime(start.year, start.month + offset),
      Freq.anual => DateTime(start.year + offset),
    };

/// Datas candidatas do período [offset] (em unidades da frequência).
List<DateTime> _period(RecurrenceRule rule, DateTime start, int offset) {
  switch (rule.freq) {
    case Freq.diaria:
      return [addDays(start, offset)];
    case Freq.semanal:
      final weekStart = addDays(startOfWeek(start), offset * 7);
      final days = rule.weekdays.isEmpty ? [start.weekday] : (rule.weekdays.toSet().toList()..sort());
      return [for (final wd in days) addDays(weekStart, wd - 1)];
    case Freq.mensal:
      final y = start.year + (start.month - 1 + offset) ~/ 12;
      final m = (start.month - 1 + offset) % 12 + 1;
      if (rule.monthlyMode == MonthlyMode.diaDaSemana) {
        final d = nthWeekdayOfMonth(y, m, start.weekday, weekOfMonth(start));
        return d == null ? const [] : [d];
      }
      if (start.day > daysInMonth(y, m)) return const [];
      return [DateTime(y, m, start.day)];
    case Freq.anual:
      final y = start.year + offset;
      if (start.day > daysInMonth(y, start.month)) return const [];
      return [DateTime(y, start.month, start.day)];
  }
}

/// Qual ocorrência do dia da semana no mês (1 = primeira ... 5 = quinta).
int weekOfMonth(DateTime d) => (d.day - 1) ~/ 7 + 1;

/// A N-ésima [weekday] do mês, ou null se não existir (ex.: 5ª segunda).
DateTime? nthWeekdayOfMonth(int year, int month, int weekday, int n) {
  final first = DateTime(year, month);
  final offset = (weekday - first.weekday) % 7;
  final day = 1 + offset + (n - 1) * 7;
  if (day > daysInMonth(year, month)) return null;
  return DateTime(year, month, day);
}

const _ordinal = ['', '1ª', '2ª', '3ª', '4ª', '5ª'];

/// "A cada 2 semanas, seg e qua, até 30/06"
String describeRecurrence(RecurrenceRule rule, DateTime start) {
  final n = rule.interval < 1 ? 1 : rule.interval;
  final parts = <String>[];
  switch (rule.freq) {
    case Freq.diaria:
      parts.add(n == 1 ? 'Todo dia' : 'A cada $n dias');
    case Freq.semanal:
      parts.add(n == 1 ? 'Toda semana' : 'A cada $n semanas');
      final days = rule.weekdays.isEmpty ? [start.weekday] : (rule.weekdays.toSet().toList()..sort());
      parts.add(joinPt(days.map((d) => weekdayShort[d]).toList()));
    case Freq.mensal:
      parts.add(n == 1 ? 'Todo mês' : 'A cada $n meses');
      if (rule.monthlyMode == MonthlyMode.diaDaSemana) {
        parts.add('na ${_ordinal[weekOfMonth(start)]} ${weekdayLong[start.weekday]}');
      } else {
        parts.add('no dia ${start.day}');
      }
    case Freq.anual:
      parts.add(n == 1 ? 'Todo ano' : 'A cada $n anos');
      parts.add('em ${dayMonth(start)}');
  }
  if (rule.until != null) parts.add('até ${dayMonth(rule.until!)}');
  if (rule.count != null) parts.add(plural0(rule.count!, 'vez').replaceFirst('vezs', 'vezes'));
  return parts.join(', ');
}

/// "seg e qua", "seg, qua e sex"
String joinPt(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
}
