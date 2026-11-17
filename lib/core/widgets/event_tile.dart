// Item de evento (listas da Agenda, Hoje e busca), com rótulo de
// acessibilidade completo: "Dentista, hoje das 14:30 às 15:30, categoria Saúde".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../data_providers.dart';
import '../providers.dart';
import '../utils/icons.dart';
import 'common.dart';

String relativeDay(DateTime d, DateTime now) {
  final diff = daysBetween(dateOnly(now), d);
  return switch (diff) {
    0 => 'hoje',
    1 => 'amanhã',
    -1 => 'ontem',
    _ => '${weekdayLong[d.weekday]}, ${dayMonth(d)}',
  };
}

String eventTimeLabel(EventOccurrence o) {
  if (o.allDay) {
    return isSameDay(o.start, o.end) ? 'Dia todo' : 'Dia todo · até ${dayMonth(o.end)}';
  }
  final sameDay = isSameDay(o.start, o.end);
  return sameDay ? '${hm(o.start)} – ${hm(o.end)}' : '${hm(o.start)} – ${dayMonth(o.end)} ${hm(o.end)}';
}

String eventSemantics(EventOccurrence o, DateTime now, Category? cat) {
  final day = relativeDay(o.start, now);
  final when = o.allDay ? '$day, dia todo' : '$day das ${hm(o.start)} às ${hm(o.end)}';
  return [
    o.title,
    when,
    if (o.event.location?.isNotEmpty ?? false) 'local ${o.event.location}',
    if (cat != null) 'categoria ${cat.name}',
  ].join(', ');
}

/// Rota de detalhe de uma ocorrência (`/evento/12?data=2026-11-17`).
String occurrenceRoute(EventOccurrence o) => '/evento/${o.event.id}?data=${toIsoDate(o.occurrenceDate)}';

class EventTile extends ConsumerWidget {
  const EventTile(this.occ, {super.key, this.showDate = false, this.highlight});
  final EventOccurrence occ;
  final bool showDate;
  final String? highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final cat = ref.watch(categoryMapProvider)[occ.categoryId];
    final color = cat == null ? c.accent : hexColor(cat.color);
    final time = eventTimeLabel(occ);
    return Semantics(
      button: true,
      label: eventSemantics(occ, now, cat),
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push(occurrenceRoute(occ)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              children: [
                CategoryStripe(color: color, height: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      highlight == null
                          ? Text(
                              occ.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                            )
                          : HighlightText(
                              occ.title,
                              highlight!,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: c.text),
                            ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 8,
                        runSpacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            showDate ? '${_cap(relativeDay(occ.start, now))} · $time' : time,
                            style: TextStyle(fontSize: 13, color: c.textSecondary, fontFeatures: tabular),
                          ),
                          if (occ.event.isRecurring) Icon(Icons.repeat, size: 14, color: c.textSecondary),
                          if (occ.event.location?.trim().isNotEmpty ?? false)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.place_outlined, size: 14, color: c.textSecondary),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    occ.event.location!.trim(),
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 13, color: c.textSecondary),
                                  ),
                                ),
                              ],
                            ),
                          if (cat != null) CategoryBadge(cat, dense: true),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
