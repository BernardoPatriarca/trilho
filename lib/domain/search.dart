// Busca com filtros combináveis (regra 6.8). Os critérios viram JSON para os
// filtros salvos.
import 'dart:convert';

import 'dates.dart';
import 'models.dart';
import 'tasks.dart';
import 'text.dart';

enum SearchPeriod { qualquer, hoje, semana, mes, personalizado }

class SearchCriteria {
  const SearchCriteria({
    this.text = '',
    this.includeTasks = true,
    this.includeEvents = true,
    this.categoryIds = const {},
    this.tagIds = const {},
    this.priorities = const {},
    this.statuses = const {},
    this.period = SearchPeriod.qualquer,
    this.from,
    this.to,
    this.withDue,
    this.onlyOverdue = false,
    this.withChecklist = false,
    this.onlyRecurring = false,
  });

  final String text;
  final bool includeTasks;
  final bool includeEvents;
  final Set<int> categoryIds;
  final Set<int> tagIds;
  final Set<int> priorities;
  final Set<TaskStatus> statuses;
  final SearchPeriod period;
  final DateTime? from;
  final DateTime? to;

  /// null = tanto faz; true = com prazo; false = sem prazo.
  final bool? withDue;
  final bool onlyOverdue;
  final bool withChecklist;
  final bool onlyRecurring;

  static const empty = SearchCriteria();

  /// Quantos filtros (além do texto) estão ligados.
  int get activeFilters =>
      (includeTasks && includeEvents ? 0 : 1) +
      (categoryIds.isEmpty ? 0 : 1) +
      (tagIds.isEmpty ? 0 : 1) +
      (priorities.isEmpty ? 0 : 1) +
      (statuses.isEmpty ? 0 : 1) +
      (period == SearchPeriod.qualquer ? 0 : 1) +
      (withDue == null ? 0 : 1) +
      (onlyOverdue ? 1 : 0) +
      (withChecklist ? 1 : 0) +
      (onlyRecurring ? 1 : 0);

  bool get isEmpty => text.trim().isEmpty && activeFilters == 0;

  /// Filtros que só fazem sentido para tarefas.
  bool get hasTaskOnlyFilters =>
      priorities.isNotEmpty || statuses.isNotEmpty || withDue != null || onlyOverdue || withChecklist;

  /// Intervalo de datas do período (inclusivo), ou null se "qualquer".
  (DateTime, DateTime)? range(DateTime now, {bool mondayFirst = true}) {
    final today = dateOnly(now);
    switch (period) {
      case SearchPeriod.qualquer:
        return null;
      case SearchPeriod.hoje:
        return (today, today);
      case SearchPeriod.semana:
        final s = startOfWeek(today, mondayFirst: mondayFirst);
        return (s, addDays(s, 6));
      case SearchPeriod.mes:
        return (startOfMonth(today), endOfMonth(today));
      case SearchPeriod.personalizado:
        if (from == null || to == null) return null;
        return (dateOnly(from!), dateOnly(to!));
    }
  }

  SearchCriteria copyWith({
    String? text,
    bool? includeTasks,
    bool? includeEvents,
    Set<int>? categoryIds,
    Set<int>? tagIds,
    Set<int>? priorities,
    Set<TaskStatus>? statuses,
    SearchPeriod? period,
    DateTime? from,
    DateTime? to,
    bool? withDue,
    bool clearWithDue = false,
    bool? onlyOverdue,
    bool? withChecklist,
    bool? onlyRecurring,
  }) =>
      SearchCriteria(
        text: text ?? this.text,
        includeTasks: includeTasks ?? this.includeTasks,
        includeEvents: includeEvents ?? this.includeEvents,
        categoryIds: categoryIds ?? this.categoryIds,
        tagIds: tagIds ?? this.tagIds,
        priorities: priorities ?? this.priorities,
        statuses: statuses ?? this.statuses,
        period: period ?? this.period,
        from: from ?? this.from,
        to: to ?? this.to,
        withDue: clearWithDue ? null : (withDue ?? this.withDue),
        onlyOverdue: onlyOverdue ?? this.onlyOverdue,
        withChecklist: withChecklist ?? this.withChecklist,
        onlyRecurring: onlyRecurring ?? this.onlyRecurring,
      );

  Map<String, Object?> toJson() => {
        'texto': text,
        'tarefas': includeTasks,
        'eventos': includeEvents,
        'categorias': categoryIds.toList()..sort(),
        'tags': tagIds.toList()..sort(),
        'prioridades': priorities.toList()..sort(),
        'status': statuses.map((s) => s.name).toList()..sort(),
        'periodo': period.name,
        'de': from == null ? null : toIsoDate(from!),
        'ate': to == null ? null : toIsoDate(to!),
        'com_prazo': withDue,
        'so_atrasadas': onlyOverdue,
        'com_checklist': withChecklist,
        'recorrentes': onlyRecurring,
      };

  String encode() => jsonEncode(toJson());

  factory SearchCriteria.fromJson(Map<String, Object?> j) {
    Set<int> ints(Object? v) => {for (final x in (v as List? ?? const [])) (x as num).toInt()};
    return SearchCriteria(
      text: (j['texto'] as String?) ?? '',
      includeTasks: (j['tarefas'] as bool?) ?? true,
      includeEvents: (j['eventos'] as bool?) ?? true,
      categoryIds: ints(j['categorias']),
      tagIds: ints(j['tags']),
      priorities: ints(j['prioridades']),
      statuses: {for (final s in (j['status'] as List? ?? const [])) TaskStatus.parse(s as String)},
      period: SearchPeriod.values.firstWhere((p) => p.name == j['periodo'], orElse: () => SearchPeriod.qualquer),
      from: j['de'] == null ? null : fromIsoDate(j['de'] as String),
      to: j['ate'] == null ? null : fromIsoDate(j['ate'] as String),
      withDue: j['com_prazo'] as bool?,
      onlyOverdue: (j['so_atrasadas'] as bool?) ?? false,
      withChecklist: (j['com_checklist'] as bool?) ?? false,
      onlyRecurring: (j['recorrentes'] as bool?) ?? false,
    );
  }

  factory SearchCriteria.decode(String s) =>
      SearchCriteria.fromJson((jsonDecode(s) as Map).cast<String, Object?>());
}

/// Dados de uma tarefa para a busca.
class TaskSearchRow {
  const TaskSearchRow({required this.task, required this.index, this.tagIds = const {}, this.checklistCount = 0});
  final Task task;

  /// Coluna `busca` (título + descrição + checklist normalizados).
  final String index;
  final Set<int> tagIds;
  final int checklistCount;
}

class EventSearchRow {
  const EventSearchRow({required this.event, required this.index, this.tagIds = const {}, this.occurrenceDates = const []});
  final Event event;
  final String index;
  final Set<int> tagIds;

  /// Datas das ocorrências dentro do período do filtro (já expandidas).
  final List<DateTime> occurrenceDates;
}

bool taskMatches(TaskSearchRow r, SearchCriteria c, DateTime now, {bool mondayFirst = true}) {
  if (!c.includeTasks) return false;
  final t = r.task;
  if (c.text.trim().isNotEmpty && !matchesSearch(r.index, c.text)) return false;
  if (c.categoryIds.isNotEmpty && !c.categoryIds.contains(t.categoryId)) return false;
  if (c.tagIds.isNotEmpty && !c.tagIds.any(r.tagIds.contains)) return false;
  if (c.priorities.isNotEmpty && !c.priorities.contains(t.priority)) return false;
  if (c.statuses.isNotEmpty && !c.statuses.contains(t.status)) return false;
  if (c.withDue == true && t.dueDate == null) return false;
  if (c.withDue == false && t.dueDate != null) return false;
  if (c.onlyOverdue && !isOverdue(t, now)) return false;
  if (c.withChecklist && r.checklistCount == 0) return false;
  if (c.onlyRecurring && !t.isRecurring) return false;
  final range = c.range(now, mondayFirst: mondayFirst);
  if (range != null) {
    if (t.dueDate == null) return false;
    final d = dateOnly(t.dueDate!);
    if (d.isBefore(range.$1) || d.isAfter(range.$2)) return false;
  }
  return true;
}

bool eventMatches(EventSearchRow r, SearchCriteria c, DateTime now, {bool mondayFirst = true}) {
  if (!c.includeEvents) return false;
  // Filtros exclusivos de tarefa (prioridade, status, prazo...) excluem eventos.
  if (c.hasTaskOnlyFilters) return false;
  final e = r.event;
  if (c.text.trim().isNotEmpty && !matchesSearch(r.index, c.text)) return false;
  if (c.categoryIds.isNotEmpty && !c.categoryIds.contains(e.categoryId)) return false;
  if (c.tagIds.isNotEmpty && !c.tagIds.any(r.tagIds.contains)) return false;
  if (c.onlyRecurring && !e.isRecurring) return false;
  final range = c.range(now, mondayFirst: mondayFirst);
  if (range != null && r.occurrenceDates.isEmpty) return false;
  return true;
}
