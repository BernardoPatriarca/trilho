// Plano de notificações (função pura): o que deve estar agendado agora.
//
// Janela rolante: só os próximos 30 dias, com teto de 400 alarmes (o Android
// limita alarmes por app). Os resumos diários dos próximos 7 dias entram
// primeiro; os lembretes preenchem o resto, do mais próximo ao mais distante.
//
// Os ids são determinísticos (hash estável de tipo + alvo + ocorrência), então
// replanejar gera os mesmos ids e o agendador só mexe no que mudou.
import 'dates.dart';
import 'models.dart';

const notificationWindowDays = 30;
const notificationCap = 400;
const summaryDays = 7;

/// Id reservado para "Testar lembrete em 1 minuto".
const testNotificationId = 1;

enum PlannedKind { lembrete, resumo, backup, teste }

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.kind,
    required this.fireAt,
    required this.title,
    required this.body,
    this.targetType,
    this.targetId,
    this.occurrence,
    required this.payload,
  });

  final int id;
  final PlannedKind kind;
  final DateTime fireAt;
  final String title;
  final String body;
  final TargetType? targetType;
  final int? targetId;

  /// Data da ocorrência (recorrentes) ou do resumo.
  final DateTime? occurrence;

  /// `tarefa:12`, `evento:3`, `hoje`.
  final String payload;

  bool get isTaskReminder => kind == PlannedKind.lembrete && targetType == TargetType.tarefa;

  /// Muda quando qualquer coisa visível muda (conteúdo, hora ou modo).
  String signature({required bool exact}) => '${toIsoDateTime(fireAt)}|$title|$body|$payload|${exact ? 'e' : 'i'}';
}

/// FNV-1a de 32 bits, positivo (cabe no `int` de id de notificação Android).
int stableId(String key) {
  var h = 0x811c9dc5;
  for (final unit in key.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  final id = h & 0x7fffffff;
  // 0..999 ficam reservados para ids fixos (teste etc.).
  return id < 1000 ? id + 1000 : id;
}

/// Lembrete de tarefa (só a instância atual de recorrentes).
class TaskReminderInput {
  const TaskReminderInput(this.task, this.reminders, {this.checklist = ChecklistProgress.empty});
  final Task task;
  final List<Reminder> reminders;
  final ChecklistProgress checklist;
}

/// Lembretes de um evento e as suas ocorrências na janela.
class EventReminderInput {
  const EventReminderInput(this.occurrences, this.reminders);
  final List<EventOccurrence> occurrences;
  final List<Reminder> reminders;
}

class SummaryInput {
  const SummaryInput(this.day, this.title, this.body);
  final DateTime day;
  final String title;
  final String body;
}

/// Hora-base de um lembrete de tarefa: a hora do prazo, ou a hora padrão
/// (`lembrete_padrao_tarefa_hora`) para tarefas só com data.
DateTime? taskBaseTime(Task t, int defaultTaskMinutes) =>
    t.dueDate == null ? null : atMinutes(t.dueDate!, t.dueMinutes ?? defaultTaskMinutes);

List<PlannedNotification> planNotifications({
  required DateTime now,
  required List<TaskReminderInput> tasks,
  required List<EventReminderInput> events,
  List<SummaryInput> summaries = const [],
  int defaultTaskMinutes = 9 * 60,
  int windowDays = notificationWindowDays,
  int cap = notificationCap,
  DateTime? backupReminderAt,
}) {
  final windowEnd = now.add(Duration(days: windowDays));
  bool inWindow(DateTime t) => t.isAfter(now) && !t.isAfter(windowEnd);

  final fixed = <PlannedNotification>[];
  for (final s in summaries) {
    final at = s.day;
    if (!inWindow(at)) continue;
    fixed.add(
      PlannedNotification(
        id: stableId('resumo:${toIsoDate(at)}'),
        kind: PlannedKind.resumo,
        fireAt: at,
        title: s.title,
        body: s.body,
        occurrence: dateOnly(at),
        payload: 'hoje',
      ),
    );
  }
  if (backupReminderAt != null && inWindow(backupReminderAt)) {
    fixed.add(
      PlannedNotification(
        id: stableId('backup:${toIsoDate(backupReminderAt)}'),
        kind: PlannedKind.backup,
        fireAt: backupReminderAt,
        title: 'Hora do backup semanal',
        body: 'Exporte um backup do Trilho em Mais › Backup e exportação.',
        payload: 'backup',
      ),
    );
  }

  final reminders = <PlannedNotification>[];
  for (final input in tasks) {
    final t = input.task;
    if (!t.isPending || t.id == null) continue;
    final base = taskBaseTime(t, defaultTaskMinutes);
    for (final r in input.reminders) {
      final at = r.isRelative ? base?.subtract(Duration(minutes: r.offsetMin!)) : r.at;
      if (at == null || !inWindow(at)) continue;
      reminders.add(
        PlannedNotification(
          id: stableId('lembrete:${r.id}:${t.id}:${toIsoDate(t.dueDate ?? at)}'),
          kind: PlannedKind.lembrete,
          fireAt: at,
          title: t.title,
          body: _taskBody(t, input.checklist, at),
          targetType: TargetType.tarefa,
          targetId: t.id,
          occurrence: t.dueDate,
          payload: 'tarefa:${t.id}',
        ),
      );
    }
  }

  for (final input in events) {
    for (final o in input.occurrences) {
      final e = o.event;
      if (e.id == null) continue;
      final base = o.allDay ? atMinutes(o.start, defaultTaskMinutes) : o.start;
      for (final r in input.reminders) {
        // Absoluto vale uma vez só (na primeira ocorrência da janela).
        if (!r.isRelative && o != input.occurrences.first) continue;
        final at = r.isRelative ? base.subtract(Duration(minutes: r.offsetMin!)) : r.at!;
        if (!inWindow(at)) continue;
        reminders.add(
          PlannedNotification(
            id: stableId('lembrete:${r.id}:e${e.id}:${toIsoDate(o.occurrenceDate)}'),
            kind: PlannedKind.lembrete,
            fireAt: at,
            title: o.title,
            body: _eventBody(o, at),
            targetType: TargetType.evento,
            targetId: e.id,
            occurrence: o.occurrenceDate,
            payload: 'evento:${e.id}:${toIsoDate(o.occurrenceDate)}',
          ),
        );
      }
    }
  }

  reminders.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  // Ids duplicados (dois lembretes idênticos) contam uma vez.
  final seen = <int>{};
  final out = <PlannedNotification>[];
  for (final n in [...fixed, ...reminders]) {
    if (out.length >= cap) break;
    if (seen.add(n.id)) out.add(n);
  }
  return out;
}

String _taskBody(Task t, ChecklistProgress p, DateTime at) {
  final parts = <String>[];
  if (t.dueDate != null) {
    final when = isSameDay(t.dueDate!, at) ? 'hoje' : dayMonth(t.dueDate!);
    parts.add(t.dueMinutes == null ? 'Prazo: $when' : 'Prazo: $when às ${minutesToHm(t.dueMinutes!)}');
  }
  if (!p.isEmpty) parts.add('${p.label} itens');
  parts.add('P${t.priority}');
  return parts.join(' · ');
}

String _eventBody(EventOccurrence o, DateTime at) {
  final parts = <String>[];
  if (o.allDay) {
    parts.add(isSameDay(o.start, at) ? 'Hoje, dia todo' : '${dayMonth(o.start)}, dia todo');
  } else {
    final day = isSameDay(o.start, at) ? 'Hoje' : dayMonth(o.start);
    parts.add('$day, ${hm(o.start)} – ${hm(o.end)}');
  }
  final loc = o.event.location;
  if (loc != null && loc.trim().isNotEmpty) parts.add(loc.trim());
  return parts.join(' · ');
}
