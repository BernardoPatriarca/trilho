// Grade de horários (visões Semana e Dia): faixa de "dia inteiro" no topo,
// eventos em blocos (sobrepostos lado a lado), tarefas com hora como
// marcadores, linha da hora atual e toque longo num horário vazio para criar
// um evento ali.
//
// Widget próprio (em vez de pacote): os pacotes de grade de horários mudam
// muito de API, e aqui o comportamento é pequeno e fácil de testar.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/utils/icons.dart';
import '../../core/widgets/event_tile.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';

const hourHeight = 56.0;
const _labelWidth = 44.0;

class TimeGrid extends ConsumerStatefulWidget {
  const TimeGrid({
    super.key,
    required this.days,
    required this.events,
    required this.tasks,
    required this.now,
    required this.onCreateAt,
  });

  final List<DateTime> days;
  final List<EventOccurrence> events;

  /// Tarefas com hora (marcadores).
  final List<Task> tasks;
  final DateTime now;
  final ValueChanged<DateTime> onCreateAt;

  @override
  ConsumerState<TimeGrid> createState() => _TimeGridState();
}

class _TimeGridState extends ConsumerState<TimeGrid> {
  late final ScrollController _scroll;

  @override
  void initState() {
    super.initState();
    final showsToday = widget.days.any((d) => isSameDay(d, widget.now));
    final h = showsToday ? (widget.now.hour - 1).clamp(0, 20) : 7;
    _scroll = ScrollController(initialScrollOffset: h * hourHeight);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cats = ref.watch(categoryMapProvider);
    final multi = widget.days.length > 1;
    final allDay = widget.events.where((e) => e.allDay).toList();

    return Column(
      children: [
        if (multi)
          Padding(
            padding: const EdgeInsets.only(left: _labelWidth),
            child: Row(
              children: [
                for (final d in widget.days)
                  Expanded(
                    child: Semantics(
                      header: true,
                      label: '${weekdayLong[d.weekday]}, ${dayMonth(d)}',
                      excludeSemantics: true,
                      child: Column(
                        children: [
                          Text(weekdayShort[d.weekday], style: TextStyle(fontSize: 12, color: c.textSecondary)),
                          Container(
                            margin: const EdgeInsets.only(top: 2, bottom: 4),
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSameDay(d, widget.now) ? c.accent : null,
                            ),
                            child: Text(
                              '${d.day}',
                              style: TextStyle(
                                fontFeatures: tabular,
                                fontWeight: FontWeight.w600,
                                color: isSameDay(d, widget.now) ? c.onAccent : c.text,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // Faixa de dia inteiro.
        if (allDay.isNotEmpty)
          Container(
            padding: const EdgeInsets.only(left: _labelWidth, bottom: 4),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final d in widget.days)
                  Expanded(
                    child: Column(
                      children: [
                        for (final e in allDay.where((e) => e.occursOn(d)))
                          _AllDayChip(
                            e,
                            color: hexColor(cats[e.categoryId]?.color, c.accent),
                            now: widget.now,
                            category: cats[e.categoryId],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(
              height: hourHeight * 24,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _labelWidth,
                    child: Stack(
                      children: [
                        for (var h = 1; h < 24; h++)
                          Positioned(
                            top: h * hourHeight - 7,
                            right: 6,
                            child: Text(
                              '${h.toString().padLeft(2, '0')}:00',
                              style: TextStyle(fontSize: 10, color: c.textSecondary, fontFeatures: tabular),
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final d in widget.days)
                    Expanded(
                      child: _DayColumn(
                        day: d,
                        events: widget.events.where((e) => !e.allDay && e.occursOn(d)).toList(),
                        tasks: widget.tasks
                            .where((t) => t.dueDate != null && isSameDay(t.dueDate!, d) && t.dueMinutes != null)
                            .toList(),
                        now: widget.now,
                        cats: cats,
                        compact: multi,
                        onCreateAt: widget.onCreateAt,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AllDayChip extends StatelessWidget {
  const _AllDayChip(this.e, {required this.color, required this.now, this.category});
  final EventOccurrence e;
  final Color color;
  final DateTime now;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: eventSemantics(e, now, category),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => context.push(occurrenceRoute(e)),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(1, 1, 1, 1),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
          child: Text(
            e.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF12161C)),
          ),
        ),
      ),
    );
  }
}

class _Placed {
  _Placed(this.e, this.start, this.end);
  final EventOccurrence e;
  final DateTime start;
  final DateTime end;
  int lane = 0;
  int lanes = 1;
}

/// Distribui eventos sobrepostos em colunas lado a lado.
List<_Placed> _layout(List<EventOccurrence> events, DateTime day) {
  final dayStart = dateOnly(day);
  final dayEnd = addDays(dayStart, 1);
  final items = [
    for (final e in events)
      _Placed(e, e.start.isBefore(dayStart) ? dayStart : e.start, e.end.isAfter(dayEnd) ? dayEnd : e.end),
  ]..sort((a, b) => a.start.compareTo(b.start));
  final clusters = <List<_Placed>>[];
  DateTime? clusterEnd;
  for (final p in items) {
    if (clusterEnd == null || !p.start.isBefore(clusterEnd)) {
      clusters.add([p]);
      clusterEnd = p.end;
    } else {
      clusters.last.add(p);
      if (p.end.isAfter(clusterEnd)) clusterEnd = p.end;
    }
  }
  for (final cl in clusters) {
    final laneEnds = <DateTime>[];
    for (final p in cl) {
      var lane = laneEnds.indexWhere((end) => !p.start.isBefore(end));
      if (lane < 0) {
        lane = laneEnds.length;
        laneEnds.add(p.end);
      } else {
        laneEnds[lane] = p.end;
      }
      p.lane = lane;
    }
    for (final p in cl) {
      p.lanes = laneEnds.length;
    }
  }
  return items;
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.events,
    required this.tasks,
    required this.now,
    required this.cats,
    required this.compact,
    required this.onCreateAt,
  });

  final DateTime day;
  final List<EventOccurrence> events;
  final List<Task> tasks;
  final DateTime now;
  final Map<int, Category> cats;
  final bool compact;
  final ValueChanged<DateTime> onCreateAt;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final placed = _layout(events, day);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPressStart: (d) {
            // Arredonda para a meia hora tocada.
            final half = (d.localPosition.dy / (hourHeight / 2)).floor().clamp(0, 47);
            onCreateAt(atMinutes(day, half * 30));
          },
          child: Stack(
            children: [
              // Linhas das horas.
              for (var h = 0; h < 24; h++)
                Positioned(
                  top: h * hourHeight,
                  left: 0,
                  right: 0,
                  child: Container(height: 1, color: c.border.withValues(alpha: 0.6)),
                ),
              Positioned(
                top: 0,
                bottom: 0,
                left: 0,
                child: Container(width: 1, color: c.border.withValues(alpha: 0.4)),
              ),
              for (final p in placed)
                Positioned(
                  top: minutesOfDay(p.start) * hourHeight / 60,
                  height: (p.end.difference(p.start).inMinutes * hourHeight / 60).clamp(22.0, hourHeight * 24),
                  left: w / p.lanes * p.lane + 1,
                  width: w / p.lanes - 2,
                  child: _EventBlock(
                    p.e,
                    color: hexColor(cats[p.e.categoryId]?.color, c.accent),
                    now: now,
                    category: cats[p.e.categoryId],
                    compact: compact,
                  ),
                ),
              for (final t in tasks)
                Positioned(
                  top: t.dueMinutes! * hourHeight / 60 - 10,
                  right: 2,
                  child: Semantics(
                    button: true,
                    label: 'Tarefa ${t.title} às ${minutesToHm(t.dueMinutes!)}',
                    excludeSemantics: true,
                    child: GestureDetector(
                      onTap: () => context.push('/tarefa/${t.id}'),
                      child: Container(
                        constraints: BoxConstraints(maxWidth: compact ? w - 4 : 220),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.surfaceHigh,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.accent),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              t.isDone ? Icons.check_circle : Icons.radio_button_unchecked,
                              size: 12,
                              color: c.accent,
                            ),
                            if (!compact) ...[
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  t.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (isSameDay(day, now))
                Positioned(
                  top: minutesOfDay(now) * hourHeight / 60 - 1,
                  left: 0,
                  right: 0,
                  child: Semantics(
                    label: 'Agora, ${hm(now)}',
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: c.error, shape: BoxShape.circle),
                        ),
                        Expanded(child: Container(height: 2, color: c.error)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EventBlock extends StatelessWidget {
  const _EventBlock(this.e, {required this.color, required this.now, required this.compact, this.category});
  final EventOccurrence e;
  final Color color;
  final DateTime now;
  final bool compact;
  final Category? category;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: eventSemantics(e, now, category),
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () => context.push(occurrenceRoute(e)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
          // Bloco curto: o texto é cortado (sem rolar) em vez de estourar.
          child: SingleChildScrollView(
            physics: const NeverScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: compact ? 3 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 10 : 13,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF12161C),
                  ),
                ),
                if (!compact)
                  Text(
                    eventTimeLabel(e),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF12161C), fontFeatures: tabular),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
