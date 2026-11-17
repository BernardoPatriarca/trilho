// Aba Estatísticas (regra 6.9): seletor de período, concluídas por dia,
// taxa no prazo, atrasadas, adiamentos, categorias, "para onde vai o seu
// tempo", sequência, mapa de calor, tempo médio e revisão semanal.
// Textos comparativos e neutros.
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/utils/icons.dart';
import '../../core/widgets/common.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/stats.dart';

class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  StatsPeriod _period = StatsPeriod.d7;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider(_period));
    return Scaffold(
      appBar: AppBar(title: const Text('ESTATÍSTICAS')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<StatsPeriod>(
                showSelectedIcon: false,
                segments: [for (final p in StatsPeriod.values) ButtonSegment(value: p, label: Text(p.label))],
                selected: {_period},
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
            ),
          ),
          Expanded(child: AsyncView(stats, builder: (s) => _body(context, s))),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ProductivityStats s) {
    final c = context.colors;
    final cats = ref.watch(categoryMapProvider);
    final hasAnything = s.total > 0 || s.overdueNow > 0 || s.eventMinutesByCategory.isNotEmpty || s.review.created > 0;
    if (!hasAnything) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.insights_outlined,
            title: 'Ainda sem números',
            message: 'Conclua algumas tarefas e as estatísticas aparecem aqui.',
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      children: [
        _ReviewCard(review: s.review, cats: cats),
        const SectionTitle('Concluídas'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                comparisonText(s.total, s.previousTotal, _period),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              SizedBox(height: 180, child: _BarChart(stats: s)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'No prazo',
                value: s.onTimeRate == null ? '—' : '${(s.onTimeRate! * 100).round()}%',
                detail: s.onTimeRate == null ? 'Nenhuma com prazo' : '${s.onTimeCount} de ${s.withDueCount} com prazo',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Sequência',
                value: '${s.streak}',
                detail: s.streak == 1 ? 'dia seguido' : 'dias seguidos',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _Metric(
                label: 'Atrasadas agora',
                value: '${s.overdueNow}',
                detail: s.overdueNow == 1 ? 'tarefa' : 'tarefas',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Metric(
                label: 'Adiamentos',
                value: s.avgPostponements.toStringAsFixed(1).replaceAll('.', ','),
                detail: 'em média por tarefa',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _Metric(
          label: 'Tempo médio entre criar e concluir',
          value: s.avgLeadTime == null ? '—' : formatDuration(s.avgLeadTime!),
          detail: s.avgLeadTime == null ? 'Sem conclusões no período' : 'nas tarefas concluídas no período',
        ),
        if (s.completedByCategory.isNotEmpty) ...[
          const SectionTitle('Concluídas por categoria'),
          AppCard(
            child: _CategoryBars(values: s.completedByCategory, cats: cats, unit: (v) => '$v'),
          ),
        ],
        if (s.eventMinutesByCategory.isNotEmpty) ...[
          const SectionTitle('Para onde vai o seu tempo'),
          AppCard(
            child: _CategoryBars(
              values: s.eventMinutesByCategory,
              cats: cats,
              unit: (v) => formatDuration(Duration(minutes: v)),
            ),
          ),
        ],
        const SectionTitle('Quando você mais produz'),
        AppCard(child: _Heatmap(heat: s.heatmap)),
        const SizedBox(height: 8),
        Text(
          'Período: ${dayMonthYear(s.from)} a ${dayMonthYear(s.to)}',
          style: TextStyle(fontSize: 12, color: c.textSecondary),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value, required this.detail});
  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: '$label: $value, $detail',
      excludeSemantics: true,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: TextStyle(fontFamily: headingFont, fontSize: 13, letterSpacing: 1, color: c.textSecondary),
            ),
            const SizedBox(height: 6),
            Text(value, style: numberStyle(context, 30)),
            Text(detail, style: TextStyle(fontSize: 12, color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review, required this.cats});
  final WeeklyReview review;
  final Map<int, Category> cats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final top = review.topCategoryId == null ? null : cats[review.topCategoryId];
    Widget cell(String n, String l) => Expanded(
      child: Column(
        children: [
          Text(n, style: numberStyle(context, 26, color: c.onAccent)),
          Text(l, style: TextStyle(fontSize: 12, color: c.onAccent)),
        ],
      ),
    );
    return Semantics(
      label:
          'Revisão semanal: ${review.completed} concluídas, ${review.created} criadas, ${review.postponed} adiadas'
          '${top == null ? '' : ', categoria mais ativa ${top.name}'}',
      excludeSemantics: true,
      child: AppCard(
        color: c.accent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'REVISÃO DA SEMANA',
              style: TextStyle(fontFamily: headingFont, fontSize: 15, letterSpacing: 1.2, color: c.onAccent),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                cell('${review.completed}', 'concluídas'),
                cell('${review.created}', 'criadas'),
                cell('${review.postponed}', 'adiadas'),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              top == null
                  ? 'Nenhuma categoria se destacou nos últimos 7 dias.'
                  : 'Categoria mais ativa: ${top.name} (${review.topCategoryCount})',
              style: TextStyle(color: c.onAccent),
            ),
          ],
        ),
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  const _BarChart({required this.stats});
  final ProductivityStats stats;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final data = stats.perDay;
    final monthly = stats.groupedByMonth;
    final maxY = data.fold<int>(0, (m, d) => d.count > m ? d.count : m);
    final step = data.length <= 7
        ? 1
        : data.length <= 31
        ? 5
        : 14;
    String label(DateTime d) => monthly
        ? monthShort[d.month]
        : data.length <= 7
        ? weekdayShort[d.weekday]
        : '${d.day}/${d.month}';
    return Semantics(
      label:
          'Gráfico de concluídas por ${monthly ? 'mês' : 'dia'}: ${stats.total} no total, máximo de $maxY num ${monthly ? 'mês' : 'dia'}',
      excludeSemantics: true,
      child: BarChart(
        BarChartData(
          maxY: (maxY == 0 ? 1 : maxY) * 1.2,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: maxY <= 5 ? 1 : (maxY / 4).ceilToDouble(),
            getDrawingHorizontalLine: (_) => FlLine(color: c.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => c.surfaceHigh,
              getTooltipItem: (g, _, rod, _) => BarTooltipItem(
                '${label(data[g.x].day)}\n${rod.toY.toInt()}',
                TextStyle(color: c.text, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: maxY <= 5 ? 1 : (maxY / 4).ceilToDouble(),
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(v.toInt().toString(), style: TextStyle(fontSize: 10, color: c.textSecondary)),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= data.length || (i % step != 0 && i != data.length - 1))
                    return const SizedBox.shrink();
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(label(data[i].day), style: TextStyle(fontSize: 10, color: c.textSecondary)),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (final (i, d) in data.indexed)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: d.count.toDouble(),
                    color: c.accent,
                    width: data.length <= 7
                        ? 18
                        : data.length <= 31
                        ? 6
                        : 3,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _CategoryBars extends StatelessWidget {
  const _CategoryBars({required this.values, required this.cats, required this.unit});
  final Map<int?, int> values;
  final Map<int, Category> cats;
  final String Function(int) unit;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final entries = values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.first.value;
    return Column(
      children: [
        for (final e in entries)
          Builder(
            builder: (context) {
              final cat = cats[e.key];
              final name = cat?.name ?? 'Sem categoria';
              final color = cat == null ? c.textSecondary : hexColor(cat.color);
              return Semantics(
                label: '$name: ${unit(e.value)}',
                excludeSemantics: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(categoryIcon(cat?.icon), size: 16, color: color),
                          const SizedBox(width: 6),
                          Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
                          Text(
                            unit(e.value),
                            style: const TextStyle(fontFeatures: tabular, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: e.value / max,
                          minHeight: 8,
                          color: color,
                          backgroundColor: c.surfaceHigh,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// Mapa de calor dia da semana × hora (faixas de 3 h, para caber no celular).
class _Heatmap extends StatelessWidget {
  const _Heatmap({required this.heat});
  final List<List<int>> heat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    // Agrupa 24 h em 8 faixas de 3 h.
    final grid = [
      for (final row in heat) [for (var b = 0; b < 8; b++) row[b * 3] + row[b * 3 + 1] + row[b * 3 + 2]],
    ];
    final max = grid.expand((r) => r).fold<int>(0, (m, v) => v > m ? v : m);
    var bestDay = 0, bestBand = 0;
    for (var d = 0; d < 7; d++) {
      for (var b = 0; b < 8; b++) {
        if (grid[d][b] > grid[bestDay][bestBand]) {
          bestDay = d;
          bestBand = b;
        }
      }
    }
    final summary = max == 0
        ? 'Sem conclusões no período.'
        : 'Pico: ${weekdayLong[bestDay + 1]}, das ${bestBand * 3}h às ${bestBand * 3 + 3}h';
    return Semantics(
      label: 'Mapa de calor das conclusões. $summary',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: 34),
              for (var b = 0; b < 8; b++)
                Expanded(
                  child: Center(
                    child: Text('${b * 3}h', style: TextStyle(fontSize: 10, color: c.textSecondary)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          for (var d = 0; d < 7; d++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    child: Text(weekdayShort[d + 1], style: TextStyle(fontSize: 11, color: c.textSecondary)),
                  ),
                  for (var b = 0; b < 8; b++)
                    Expanded(
                      child: Container(
                        height: 22,
                        margin: const EdgeInsets.symmetric(horizontal: 1.5),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          color: grid[d][b] == 0
                              ? c.surfaceHigh
                              : c.accent.withValues(alpha: 0.25 + 0.75 * grid[d][b] / max),
                        ),
                        alignment: Alignment.center,
                        child: grid[d][b] == 0
                            ? null
                            : Text(
                                '${grid[d][b]}',
                                style: TextStyle(fontSize: 10, color: c.onAccent, fontFeatures: tabular),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(summary, style: TextStyle(fontSize: 13, color: c.textSecondary)),
        ],
      ),
    );
  }
}
