// Exportação de eventos em iCalendar (.ics, RFC 5545), com RRULE para os
// recorrentes, EXDATE para ocorrências canceladas e RECURRENCE-ID para as
// alteradas. Horários "flutuantes" com TZID do fuso local.
import 'dates.dart';
import 'event_expansion.dart';
import 'models.dart';

const _byDay = ['', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}${_two(d.month)}${_two(d.day)}';
String _dateTime(DateTime d) => '${_date(d)}T${_two(d.hour)}${_two(d.minute)}00';

String icsEscape(String s) => s
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll(RegExp(r'\r?\n'), '\\n');

/// Dobra linhas em 75 octetos (aproximado por caracteres UTF-16, seguro
/// porque continua dentro do limite para texto em português).
String _fold(String line) {
  if (line.length <= 73) return line;
  final b = StringBuffer();
  var i = 0;
  var first = true;
  while (i < line.length) {
    final n = first ? 73 : 72;
    final end = i + n > line.length ? line.length : i + n;
    if (!first) b.write('\r\n ');
    b.write(line.substring(i, end));
    i = end;
    first = false;
  }
  return b.toString();
}

String rruleOf(RecurrenceRule r, DateTime start) {
  final parts = <String>['FREQ=${switch (r.freq) {
    Freq.diaria => 'DAILY',
    Freq.semanal => 'WEEKLY',
    Freq.mensal => 'MONTHLY',
    Freq.anual => 'YEARLY',
  }}'];
  if (r.interval > 1) parts.add('INTERVAL=${r.interval}');
  switch (r.freq) {
    case Freq.semanal:
      final days = r.weekdays.isEmpty ? [start.weekday] : (r.weekdays.toSet().toList()..sort());
      parts.add('BYDAY=${days.map((d) => _byDay[d]).join(',')}');
    case Freq.mensal:
      if (r.monthlyMode == MonthlyMode.diaDaSemana) {
        parts.add('BYDAY=${(start.day - 1) ~/ 7 + 1}${_byDay[start.weekday]}');
      } else {
        parts.add('BYMONTHDAY=${start.day}');
      }
    case Freq.anual:
      parts.add('BYMONTH=${start.month};BYMONTHDAY=${start.day}');
    case Freq.diaria:
      break;
  }
  if (r.until != null) parts.add('UNTIL=${_date(r.until!)}T235959');
  if (r.count != null) parts.add('COUNT=${r.count}');
  return 'RRULE:${parts.join(';')}';
}

String exportIcs(
  List<EventSeries> series, {
  required DateTime now,
  String timezone = 'America/Sao_Paulo',
  Map<int, String> categoryNames = const {},
}) {
  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Trilho//Agenda pessoal//PT-BR',
    'CALSCALE:GREGORIAN',
    'X-WR-CALNAME:Trilho',
    'X-WR-TIMEZONE:$timezone',
  ];
  final stamp = '${_dateTime(now.toUtc())}Z';

  void when(String name, DateTime d, bool allDay) {
    lines.add(allDay ? '$name;VALUE=DATE:${_date(d)}' : '$name;TZID=$timezone:${_dateTime(d)}');
  }

  for (final s in series) {
    final e = s.event;
    final uid = 'evento-${e.id}@trilho';
    void body({required DateTime start, required DateTime end, required String title}) {
      when('DTSTART', start, e.allDay);
      // DTEND é exclusivo: no dia inteiro, o dia seguinte ao último.
      when('DTEND', e.allDay ? addDays(end, 1) : end, e.allDay);
      lines.add('SUMMARY:${icsEscape(title)}');
      if (e.location?.trim().isNotEmpty ?? false) lines.add('LOCATION:${icsEscape(e.location!)}');
      if (e.description?.trim().isNotEmpty ?? false) lines.add('DESCRIPTION:${icsEscape(e.description!)}');
      final cat = categoryNames[e.categoryId];
      if (cat != null) lines.add('CATEGORIES:${icsEscape(cat)}');
    }

    lines.add('BEGIN:VEVENT');
    lines.add('UID:$uid');
    lines.add('DTSTAMP:$stamp');
    body(start: e.start, end: e.end, title: e.title);
    if (s.rule != null) {
      lines.add(rruleOf(s.rule!, e.start));
      for (final x in s.exceptions.where((x) => x.cancelled)) {
        final orig = e.allDay ? x.occurrenceDate : atMinutes(x.occurrenceDate, minutesOfDay(e.start));
        when('EXDATE', orig, e.allDay);
      }
    }
    lines.add('END:VEVENT');

    // Ocorrências alteradas viram VEVENTs próprios com RECURRENCE-ID.
    if (s.rule != null) {
      for (final x in s.exceptions.where((x) => !x.cancelled)) {
        final orig = e.allDay ? x.occurrenceDate : atMinutes(x.occurrenceDate, minutesOfDay(e.start));
        final start = x.newStart ?? orig;
        final end = x.newEnd ?? (e.allDay ? addDays(start, e.duration.inDays) : start.add(e.duration));
        lines.add('BEGIN:VEVENT');
        lines.add('UID:$uid');
        lines.add('DTSTAMP:$stamp');
        when('RECURRENCE-ID', orig, e.allDay);
        body(start: start, end: end, title: x.newTitle ?? e.title);
        lines.add('END:VEVENT');
      }
    }
  }
  lines.add('END:VCALENDAR');
  return '${lines.map(_fold).join('\r\n')}\r\n';
}
