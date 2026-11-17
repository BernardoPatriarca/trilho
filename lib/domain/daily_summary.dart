// Resumo diário das 7h (regra 6.10): título e até 6 linhas.
import 'dates.dart';
import 'models.dart';
import 'tasks.dart';
import 'text.dart';

class DailySummary {
  const DailySummary(this.title, this.lines);
  final String title;
  final List<String> lines;

  String get body => lines.join('\n');
}

const maxSummaryLines = 6;
const emptyDayText = 'Dia livre na agenda. Que tal adiantar algo da semana?';

/// [day] é o dia do resumo. Atrasadas = pendentes com prazo antes dele.
/// [checklist]: progresso por id de tarefa.
DailySummary buildDailySummary({
  required DateTime day,
  required List<Task> tasks,
  required List<EventOccurrence> events,
  Map<int, ChecklistProgress> checklist = const {},
}) {
  final d = dateOnly(day);
  final dayTasks = tasks.where((t) => t.isPending && t.dueDate != null && isSameDay(t.dueDate!, d)).toList()
    ..sort(compareByDue);
  final overdue = tasks.where((t) => t.isPending && t.dueDate != null && dateOnly(t.dueDate!).isBefore(d)).length;
  final dayEvents = events.where((e) => e.occursOn(d)).toList()
    ..sort((a, b) {
      if (a.allDay != b.allDay) return a.allDay ? 1 : -1;
      return a.start.compareTo(b.start);
    });

  if (dayTasks.isEmpty && dayEvents.isEmpty && overdue == 0) {
    return const DailySummary('Bom dia!', [emptyDayText]);
  }

  final counts = <String>[
    if (dayTasks.isNotEmpty || dayEvents.isEmpty) plural(dayTasks.length, 'tarefa'),
    if (dayEvents.isNotEmpty) plural(dayEvents.length, 'evento'),
  ];
  final title = 'Bom dia! Hoje: ${counts.join(' e ')}';

  final content = <String>[
    for (final e in dayEvents)
      e.allDay ? 'Dia todo · ${e.title}' : '${isSameDay(e.start, d) ? hm(e.start) : '00:00'} · ${e.title}',
    for (final t in dayTasks.where((t) => t.priority <= 2))
      'P${t.priority} · ${t.title}${_checklistSuffix(checklist[t.id])}',
  ];
  final overdueLine = overdue == 0 ? null : '⚠ ${plural(overdue, 'tarefa')} atrasada${overdue == 1 ? '' : 's'}';

  final room = maxSummaryLines - (overdueLine == null ? 0 : 1);
  final lines = <String>[];
  if (content.length <= room) {
    lines.addAll(content);
  } else {
    lines.addAll(content.take(room - 1));
    lines.add('+ ${content.length - (room - 1)} mais');
  }
  if (overdueLine != null) lines.add(overdueLine);
  return DailySummary(title, lines);
}

String _checklistSuffix(ChecklistProgress? p) =>
    p == null || p.isEmpty ? '' : ' (${p.label} itens)';
