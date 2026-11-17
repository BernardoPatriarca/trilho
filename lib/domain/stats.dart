// Estatísticas de produtividade (regra 6.9). Textos sempre comparativos e
// neutros, sem julgamento.
import 'dates.dart';
import 'models.dart';
import 'tasks.dart';

enum StatsPeriod {
  d7(7, '7 dias', 'nos 7 dias anteriores'),
  d30(30, '30 dias', 'nos 30 dias anteriores'),
  d90(90, '90 dias', 'nos 90 dias anteriores'),
  all(null, 'Tudo', '');

  const StatsPeriod(this.days, this.label, this.previousLabel);
  final int? days;
  final String label;
  final String previousLabel;
}

class DayCount {
  const DayCount(this.day, this.count);
  final DateTime day;
  final int count;
}

class WeeklyReview {
  const WeeklyReview({
    required this.completed,
    required this.created,
    required this.postponed,
    required this.topCategoryId,
    required this.topCategoryCount,
  });
  final int completed;
  final int created;
  final int postponed;

  /// null = sem categoria / nenhuma conclusão.
  final int? topCategoryId;
  final int topCategoryCount;
}

class ProductivityStats {
  const ProductivityStats({
    required this.from,
    required this.to,
    required this.perDay,
    required this.total,
    required this.previousTotal,
    required this.onTimeRate,
    required this.onTimeCount,
    required this.withDueCount,
    required this.overdueNow,
    required this.avgPostponements,
    required this.completedByCategory,
    required this.eventMinutesByCategory,
    required this.streak,
    required this.heatmap,
    required this.avgLeadTime,
    required this.review,
  });

  final DateTime from;
  final DateTime to;

  /// Concluídas por dia (ou por mês em "Tudo" com mais de 90 dias).
  final List<DayCount> perDay;
  final int total;

  /// null em "Tudo".
  final int? previousTotal;

  /// Concluídas até o prazo / concluídas que tinham prazo (null se nenhuma).
  final double? onTimeRate;
  final int onTimeCount;
  final int withDueCount;
  final int overdueNow;
  final double avgPostponements;

  /// Chave null = sem categoria.
  final Map<int?, int> completedByCategory;
  final Map<int?, int> eventMinutesByCategory;

  /// Dias seguidos com pelo menos uma conclusão (até hoje, ou até ontem se
  /// hoje ainda não teve).
  final int streak;

  /// [dia da semana 0 = segunda][hora 0..23] → conclusões.
  final List<List<int>> heatmap;
  final Duration? avgLeadTime;
  final WeeklyReview review;

  bool get groupedByMonth =>
      perDay.isNotEmpty && perDay.length > 1 && perDay[0].day.day == 1 && to.difference(from).inDays > 90;
}

ProductivityStats computeStats({
  required List<Task> tasks,
  required List<EventOccurrence> events,
  required DateTime now,
  required StatsPeriod period,
}) {
  final today = dateOnly(now);
  final completed = tasks.where((t) => t.isDone && t.completedAt != null).toList();

  late DateTime from;
  if (period.days != null) {
    from = addDays(today, -(period.days! - 1));
  } else {
    final starts = [...completed.map((t) => dateOnly(t.completedAt!)), ...tasks.map((t) => dateOnly(t.createdAt))];
    from = starts.isEmpty ? today : starts.reduce((a, b) => a.isBefore(b) ? a : b);
  }
  final to = today;
  bool inRange(DateTime d, DateTime a, DateTime b) {
    final x = dateOnly(d);
    return !x.isBefore(a) && !x.isAfter(b);
  }

  final inPeriod = completed.where((t) => inRange(t.completedAt!, from, to)).toList();

  // Concluídas por dia (ou por mês, se "Tudo" for longo).
  final span = daysBetween(from, to) + 1;
  final perDay = <DayCount>[];
  if (period == StatsPeriod.all && span > 90) {
    var m = DateTime(from.year, from.month);
    while (!m.isAfter(to)) {
      final next = DateTime(m.year, m.month + 1);
      perDay.add(
        DayCount(m, inPeriod.where((t) => !t.completedAt!.isBefore(m) && t.completedAt!.isBefore(next)).length),
      );
      m = next;
    }
  } else {
    final counts = <String, int>{};
    for (final t in inPeriod) {
      final k = toIsoDate(t.completedAt!);
      counts[k] = (counts[k] ?? 0) + 1;
    }
    for (var i = 0; i < span; i++) {
      final d = addDays(from, i);
      perDay.add(DayCount(d, counts[toIsoDate(d)] ?? 0));
    }
  }

  int? previousTotal;
  if (period.days != null) {
    final pTo = addDays(from, -1);
    final pFrom = addDays(pTo, -(period.days! - 1));
    previousTotal = completed.where((t) => inRange(t.completedAt!, pFrom, pTo)).length;
  }

  // Taxa no prazo.
  final withDue = inPeriod.where((t) => t.dueDate != null).toList();
  final onTime = withDue.where((t) => !t.completedAt!.isAfter(dueDeadline(t)!)).length;

  final overdueNow = tasks.where((t) => isOverdue(t, now)).length;

  // Média de adiamentos das tarefas criadas no período.
  final created = tasks.where((t) => inRange(t.createdAt, from, to)).toList();
  final avgPost = created.isEmpty ? 0.0 : created.map((t) => t.postponements).reduce((a, b) => a + b) / created.length;

  final byCat = <int?, int>{};
  for (final t in inPeriod) {
    byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + 1;
  }

  // Tempo de eventos por categoria (só eventos com hora, dentro do período).
  final evMin = <int?, int>{};
  final periodEnd = addDays(to, 1);
  for (final e in events) {
    if (e.allDay) continue;
    final s = e.start.isBefore(from) ? from : e.start;
    final en = e.end.isAfter(periodEnd) ? periodEnd : e.end;
    if (!en.isAfter(s)) continue;
    evMin[e.categoryId] = (evMin[e.categoryId] ?? 0) + en.difference(s).inMinutes;
  }

  // Sequência (sobre todo o histórico).
  final doneDays = {for (final t in completed) toIsoDate(t.completedAt!)};
  var streak = 0;
  var cursor = doneDays.contains(toIsoDate(today)) ? today : addDays(today, -1);
  while (doneDays.contains(toIsoDate(cursor))) {
    streak++;
    cursor = addDays(cursor, -1);
  }

  final heat = List.generate(7, (_) => List.filled(24, 0));
  for (final t in inPeriod) {
    heat[t.completedAt!.weekday - 1][t.completedAt!.hour]++;
  }

  Duration? lead;
  if (inPeriod.isNotEmpty) {
    final totalMin = inPeriod.map((t) => t.completedAt!.difference(t.createdAt).inMinutes).reduce((a, b) => a + b);
    lead = Duration(minutes: totalMin ~/ inPeriod.length);
  }

  return ProductivityStats(
    from: from,
    to: to,
    perDay: perDay,
    total: inPeriod.length,
    previousTotal: previousTotal,
    onTimeRate: withDue.isEmpty ? null : onTime / withDue.length,
    onTimeCount: onTime,
    withDueCount: withDue.length,
    overdueNow: overdueNow,
    avgPostponements: avgPost,
    completedByCategory: byCat,
    eventMinutesByCategory: evMin,
    streak: streak,
    heatmap: heat,
    avgLeadTime: lead,
    review: weeklyReview(tasks, now),
  );
}

/// Revisão dos últimos 7 dias (hoje incluso).
WeeklyReview weeklyReview(List<Task> tasks, DateTime now) {
  final to = dateOnly(now);
  final from = addDays(to, -6);
  bool inWeek(DateTime d) => !dateOnly(d).isBefore(from) && !dateOnly(d).isAfter(to);
  final done = tasks.where((t) => t.isDone && t.completedAt != null && inWeek(t.completedAt!)).toList();
  final created = tasks.where((t) => inWeek(t.createdAt)).length;
  // Sem histórico de cada adiamento: conta as tarefas adiadas alguma vez e
  // alteradas nesta semana.
  final postponed = tasks.where((t) => t.postponements > 0 && inWeek(t.updatedAt)).length;
  final byCat = <int?, int>{};
  for (final t in done) {
    byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + 1;
  }
  int? top;
  var topN = 0;
  byCat.forEach((k, v) {
    if (k != null && v > topN) {
      top = k;
      topN = v;
    }
  });
  return WeeklyReview(
    completed: done.length,
    created: created,
    postponed: postponed,
    topCategoryId: top,
    topCategoryCount: topN,
  );
}

/// "12 concluídas, 3 a mais que nos 7 dias anteriores"
String comparisonText(int current, int? previous, StatsPeriod period) {
  final base = '$current concluída${current == 1 ? '' : 's'}';
  if (previous == null) return base;
  final diff = current - previous;
  if (diff == 0) return '$base, o mesmo número que ${period.previousLabel}';
  final n = diff.abs();
  return '$base, $n a ${diff > 0 ? 'mais' : 'menos'} que ${period.previousLabel}';
}

/// "2 h 30 min", "3 dias", "45 min"
String formatDuration(Duration d) {
  if (d.inDays >= 2) return '${d.inDays} dias';
  if (d.inHours >= 1) {
    final m = d.inMinutes % 60;
    return m == 0 ? '${d.inHours} h' : '${d.inHours} h $m min';
  }
  return '${d.inMinutes} min';
}
