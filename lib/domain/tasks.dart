// Regras das tarefas: atrasadas, adiar e próxima instância de recorrentes.
import 'dates.dart';
import 'models.dart';
import 'recurrence.dart';

/// Regra 3: pendente e com prazo antes de hoje, ou hoje com hora já passada.
bool isOverdue(Task t, DateTime now) {
  if (!t.isPending || t.dueDate == null) return false;
  final today = dateOnly(now);
  final due = dateOnly(t.dueDate!);
  if (due.isBefore(today)) return true;
  if (isSameDay(due, today) && t.dueMinutes != null) {
    return t.dueMinutes! < minutesOfDay(now);
  }
  return false;
}

/// Momento-limite do prazo: com hora, a própria hora; só data, fim do dia.
DateTime? dueDeadline(Task t) {
  if (t.dueDate == null) return null;
  if (t.dueMinutes != null) return atMinutes(t.dueDate!, t.dueMinutes!);
  return DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day, 23, 59, 59);
}

/// Próximo prazo de uma tarefa recorrente, calculado a partir do **prazo
/// original** (não da data de conclusão). Null se a série acabou.
DateTime? nextDueDate(Task t, RecurrenceRule rule) {
  if (t.dueDate == null) return null;
  if (rule.count != null && rule.count! <= 1) return null;
  return nextOccurrenceAfter(rule, t.dueDate!, t.dueDate!);
}

/// Regra da próxima instância: a nova tarefa herda tudo, com prazo novo.
/// A contagem restante diminui em 1 (a regra é copiada para a instância nova).
RecurrenceRule nextInstanceRule(RecurrenceRule rule) =>
    rule.count == null ? rule.withoutId() : rule.withoutId().copyWith(count: rule.count! - 1);

Task nextInstance(Task t, DateTime nextDue, DateTime now, int recurrenceId) => Task(
  title: t.title,
  description: t.description,
  categoryId: t.categoryId,
  priority: t.priority,
  dueDate: nextDue,
  dueMinutes: t.dueMinutes,
  createdAt: now,
  updatedAt: now,
  estimateMin: t.estimateMin,
  recurrenceId: recurrenceId,
  order: t.order,
);

/// Checklist copiada com **todos os itens desmarcados**.
List<ChecklistItem> resetChecklist(List<ChecklistItem> items) => [
  for (final (i, it) in items.indexed) ChecklistItem(text: it.text, quantity: it.quantity, checked: false, order: i),
];

/// Lembretes copiados para a próxima instância. Relativos continuam iguais;
/// absolutos andam junto com o prazo.
List<Reminder> shiftReminders(List<Reminder> reminders, DateTime oldDue, DateTime newDue) {
  final delta = daysBetween(oldDue, newDue);
  return [
    for (final r in reminders)
      r.isRelative ? Reminder.relative(r.offsetMin!) : Reminder.absolute(addDays(r.at!, delta)),
  ];
}

/// Um destino de "Adiar".
class PostponeOption {
  const PostponeOption(this.label, this.date, this.minutes);
  final String label;
  final DateTime date;
  final int? minutes;
}

/// Atalhos de adiar (regra 4): +1 hora, Hoje à noite (19h), Amanhã, Próxima
/// segunda. "Escolher data" fica na tela.
List<PostponeOption> postponeOptions(Task t, DateTime now, {int defaultMinutes = 60}) {
  final opts = <PostponeOption>[];
  final plus = now.add(Duration(minutes: defaultMinutes));
  final plusLabel = defaultMinutes % 60 == 0
      ? '+${defaultMinutes ~/ 60} hora${defaultMinutes == 60 ? '' : 's'}'
      : '+$defaultMinutes min';
  opts.add(PostponeOption(plusLabel, dateOnly(plus), minutesOfDay(plus)));
  if (now.hour < 19) {
    opts.add(PostponeOption('Hoje à noite (19h)', dateOnly(now), 19 * 60));
  }
  opts.add(PostponeOption('Amanhã', addDays(dateOnly(now), 1), t.dueMinutes));
  opts.add(PostponeOption('Próxima segunda', nextWeekday(now, DateTime.monday), t.dueMinutes));
  return opts;
}

/// Aplica um novo prazo. Mover para frente incrementa `adiamentos`.
Task postpone(Task t, DateTime date, int? minutes, DateTime now) {
  final oldDeadline = t.dueDate == null ? null : atMinutes(t.dueDate!, t.dueMinutes ?? 0);
  final newDeadline = atMinutes(date, minutes ?? 0);
  final forward = oldDeadline == null || newDeadline.isAfter(oldDeadline);
  return t.copyWith(
    dueDate: dateOnly(date),
    dueMinutes: minutes,
    clearTime: minutes == null,
    postponements: forward ? t.postponements + 1 : t.postponements,
    updatedAt: now,
  );
}

/// Validações com mensagens em português.
String? validateTask({required String title, DateTime? dueDate, int? dueMinutes, RecurrenceRule? rule}) {
  if (title.trim().isEmpty) return 'Informe o título da tarefa.';
  if (dueMinutes != null && dueDate == null) return 'A hora do prazo precisa de uma data.';
  if (rule != null && dueDate == null) return 'Tarefa recorrente precisa de uma data de prazo.';
  return null;
}

String? validateEvent({required String title, required DateTime start, required DateTime end, required bool allDay}) {
  if (title.trim().isEmpty) return 'Informe o título do evento.';
  if (allDay) {
    if (dateOnly(end).isBefore(dateOnly(start))) return 'O fim precisa ser depois do início.';
  } else if (!end.isAfter(start)) {
    return 'O fim precisa ser depois do início.';
  }
  return null;
}

String? validateRule(RecurrenceRule? rule, DateTime start) {
  if (rule == null) return null;
  if (rule.interval < 1) return 'O intervalo precisa ser pelo menos 1.';
  if (rule.count != null && rule.count! < 1) return 'O número de vezes precisa ser pelo menos 1.';
  if (rule.until != null && dateOnly(rule.until!).isBefore(dateOnly(start))) {
    return 'A data final da repetição é antes do início.';
  }
  return null;
}

/// Ordenação padrão: prioridade (P1 primeiro) e depois ordem manual.
int compareByPriority(Task a, Task b) {
  final p = a.priority.compareTo(b.priority);
  if (p != 0) return p;
  final o = a.order.compareTo(b.order);
  if (o != 0) return o;
  return (a.id ?? 0).compareTo(b.id ?? 0);
}

/// Ordenação por prazo (sem prazo no fim), depois prioridade.
int compareByDue(Task a, Task b) {
  final da = a.dueDateTime, db = b.dueDateTime;
  if (da == null && db != null) return 1;
  if (da != null && db == null) return -1;
  if (da != null && db != null) {
    final c = da.compareTo(db);
    if (c != 0) return c;
  }
  return compareByPriority(a, b);
}
