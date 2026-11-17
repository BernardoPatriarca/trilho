// Providers de leitura. Todos observam a revisão dos dados, então recarregam
// depois de qualquer escrita.
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/dates.dart';
import '../domain/event_expansion.dart';
import '../domain/models.dart';
import '../domain/stats.dart';
import '../domain/today.dart';
import '../features/search/search_repository.dart';
import '../features/tasks/task_repository.dart';
import 'providers.dart';

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(categoryRepositoryProvider).all();
});

/// Mapa id → categoria (inclui inativas, para itens antigos).
final categoryMapProvider = Provider<Map<int, Category>>((ref) {
  final list = ref.watch(categoriesProvider).value ?? const [];
  return {for (final c in list) c.id!: c};
});

final tagsProvider = FutureProvider<List<Tag>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(tagRepositoryProvider).all();
});

final tagUsageProvider = FutureProvider<Map<int, int>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(tagRepositoryProvider).usage();
});

final taskListProvider = FutureProvider<TaskListData>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(taskRepositoryProvider).listData();
});

/// Ocorrências de eventos num intervalo de datas (inclusivo).
final occurrencesProvider = FutureProvider.family<List<EventOccurrence>, (DateTime, DateTime)>((ref, range) async {
  ref.watch(dataRevisionProvider);
  final series = await ref.watch(eventRepositoryProvider).seriesInRange(range.$1, range.$2);
  return expandEvents(series, range.$1, range.$2);
});

final todayProvider = FutureProvider<(TodayView, TaskListData)>((ref) async {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final today = dateOnly(now);
  final data = await ref.watch(taskListProvider.future);
  final events = await ref.watch(occurrencesProvider((today, today)).future);
  return (buildToday(tasks: data.tasks, events: events, now: now), data);
});

final templatesProvider = FutureProvider<List<ChecklistTemplate>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(templateRepositoryProvider).all();
});

final savedFiltersProvider = FutureProvider<List<SavedFilter>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(searchRepositoryProvider).savedFilters();
});

final statsProvider = FutureProvider.family<ProductivityStats, StatsPeriod>((ref, period) async {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  final data = await ref.watch(taskListProvider.future);
  final today = dateOnly(now);
  final from = period.days == null
      ? data.tasks.map((t) => dateOnly(t.createdAt)).fold<DateTime>(today, (a, b) => b.isBefore(a) ? b : a)
      : addDays(today, -(period.days! - 1));
  final events = await ref.watch(occurrencesProvider((from, today)).future);
  return computeStats(tasks: data.tasks, events: events, now: now, period: period);
});
