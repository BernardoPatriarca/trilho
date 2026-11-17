// Expansão de eventos (únicos e recorrentes) num intervalo de datas, já com
// as exceções "só este evento" aplicadas.
import 'dates.dart';
import 'models.dart';
import 'recurrence.dart';

/// Um evento com a sua regra e as suas exceções.
class EventSeries {
  const EventSeries(this.event, {this.rule, this.exceptions = const []});
  final Event event;
  final RecurrenceRule? rule;
  final List<EventException> exceptions;
}

/// Ocorrências que tocam o intervalo [from]..[to] (datas inclusivas),
/// ordenadas por início.
List<EventOccurrence> expandEvents(
  Iterable<EventSeries> series,
  DateTime from,
  DateTime to,
) {
  final f = dateOnly(from);
  final t = dateOnly(to);
  final rangeEnd = addDays(t, 1); // exclusivo
  final out = <EventOccurrence>[];
  for (final s in series) {
    out.addAll(expandOne(s, f, t, rangeEnd));
  }
  out.sort((a, b) {
    final c = a.start.compareTo(b.start);
    if (c != 0) return c;
    // Dia inteiro primeiro.
    if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
    return a.title.compareTo(b.title);
  });
  return out;
}

Iterable<EventOccurrence> expandOne(
    EventSeries s, DateTime f, DateTime t, DateTime rangeEnd) sync* {
  final e = s.event;
  final duration = e.duration;
  final spanDays = duration.inDays + 1;
  final byDate = {for (final x in s.exceptions) toIsoDate(x.occurrenceDate): x};

  // Amplia a busca para pegar eventos longos que começaram antes do
  // intervalo e ocorrências movidas por exceção para dentro dele.
  final searchFrom = addDays(f, -spanDays - 7);
  final searchTo = addDays(t, 7);
  final dates = occurrencesBetween(s.rule, e.start, searchFrom, searchTo);

  for (final d in dates) {
    final ex = byDate[toIsoDate(d)];
    if (ex != null && ex.cancelled) continue;
    var start = e.allDay ? d : atMinutes(d, minutesOfDay(e.start));
    var end = e.allDay ? addDays(d, duration.inDays) : start.add(duration);
    var title = e.title;
    var modified = false;
    if (ex != null) {
      if (ex.newStart != null) start = ex.newStart!;
      if (ex.newEnd != null) end = ex.newEnd!;
      if (ex.newTitle != null && ex.newTitle!.trim().isNotEmpty) title = ex.newTitle!;
      modified = true;
    }
    final occ = EventOccurrence(
      event: e,
      start: start,
      end: end,
      occurrenceDate: d,
      title: title,
      modified: modified,
    );
    if (_overlaps(occ, f, rangeEnd)) yield occ;
  }
}

bool _overlaps(EventOccurrence o, DateTime from, DateTime endExclusive) {
  if (o.allDay) {
    return !dateOnly(o.end).isBefore(from) && dateOnly(o.start).isBefore(endExclusive);
  }
  if (o.start == o.end) {
    return !o.start.isBefore(from) && o.start.isBefore(endExclusive);
  }
  return o.start.isBefore(endExclusive) && o.end.isAfter(from);
}
