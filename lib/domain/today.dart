// Montagem da tela Hoje (regra 6.5).
import 'dates.dart';
import 'models.dart';
import 'tasks.dart';

/// Item da linha do tempo: evento com hora ou tarefa com hora.
class TimelineEntry {
  const TimelineEntry.event(EventOccurrence this.event)
      : task = null,
        time = null;
  TimelineEntry.task(Task this.task)
      : event = null,
        time = task.dueDateTime;

  final EventOccurrence? event;
  final Task? task;
  final DateTime? time;

  DateTime get sortKey => event?.start ?? time!;
}

class TodayView {
  const TodayView({
    required this.day,
    required this.overdue,
    required this.allDayEvents,
    required this.timeline,
    required this.untimed,
    required this.pinned,
    required this.completedToday,
  });

  final DateTime day;

  /// 1. Atrasadas.
  final List<Task> overdue;

  /// Eventos de dia inteiro (no topo da linha do tempo).
  final List<EventOccurrence> allDayEvents;

  /// 2. Eventos e tarefas com hora, em ordem cronológica.
  final List<TimelineEntry> timeline;

  /// 3. Tarefas de hoje sem hora (P1 primeiro, depois ordem manual).
  final List<Task> untimed;

  /// 4. Fixadas para hoje.
  final List<Task> pinned;

  /// 5. Concluídas hoje.
  final List<Task> completedToday;

  /// Tarefas pendentes que contam para o dia.
  int get pendingCount =>
      overdue.length + timeline.where((e) => e.task != null).length + untimed.length + pinned.length;

  int get doneCount => completedToday.length;
  int get totalCount => pendingCount + doneCount;
  double get progress => totalCount == 0 ? 0 : doneCount / totalCount;
  int get eventCount => allDayEvents.length + timeline.where((e) => e.event != null).length;

  bool get isEmpty => totalCount == 0 && eventCount == 0;
}

/// [events] são as ocorrências já expandidas (pode incluir outros dias).
TodayView buildToday({
  required List<Task> tasks,
  required List<EventOccurrence> events,
  required DateTime now,
}) {
  final today = dateOnly(now);
  final overdue = <Task>[];
  final timedTasks = <Task>[];
  final untimed = <Task>[];
  final pinned = <Task>[];
  final completed = <Task>[];

  for (final t in tasks) {
    if (t.isDone) {
      if (t.completedAt != null && isSameDay(t.completedAt!, today)) completed.add(t);
      continue;
    }
    if (!t.isPending) continue;
    if (isOverdue(t, now)) {
      overdue.add(t);
    } else if (t.dueDate != null && isSameDay(t.dueDate!, today)) {
      (t.dueMinutes != null ? timedTasks : untimed).add(t);
    } else if (t.pinnedToday) {
      pinned.add(t);
    }
  }

  final todays = events.where((e) => e.occursOn(today)).toList();
  final allDay = todays.where((e) => e.allDay).toList();
  final timeline = <TimelineEntry>[
    for (final e in todays.where((e) => !e.allDay)) TimelineEntry.event(e),
    for (final t in timedTasks) TimelineEntry.task(t),
  ]..sort((a, b) {
      final c = a.sortKey.compareTo(b.sortKey);
      if (c != 0) return c;
      // Eventos antes de tarefas no mesmo horário.
      if ((a.event == null) != (b.event == null)) return a.event != null ? -1 : 1;
      return 0;
    });

  overdue.sort(compareByDue);
  untimed.sort(compareByPriority);
  pinned.sort(compareByPriority);
  completed.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));

  return TodayView(
    day: today,
    overdue: overdue,
    allDayEvents: allDay,
    timeline: timeline,
    untimed: untimed,
    pinned: pinned,
    completedToday: completed,
  );
}
