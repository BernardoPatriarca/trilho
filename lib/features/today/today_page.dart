// Aba Hoje (regra 6.5): atrasadas, linha do tempo, tarefas sem hora,
// fixadas e concluídas (recolhidas). No topo: data, contador e anel.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/event_tile.dart';
import '../../core/widgets/task_tile.dart';
import '../../domain/dates.dart';
import '../../domain/today.dart';
import '../tasks/task_repository.dart';

class TodayPage extends ConsumerStatefulWidget {
  const TodayPage({super.key});

  @override
  ConsumerState<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends ConsumerState<TodayPage> {
  bool _showDone = false;

  Future<void> _rescheduleAll() async {
    final c = ref.container;
    final messenger = ScaffoldMessenger.of(context);
    final repo = c.read(taskRepositoryProvider);
    final before = await repo.rescheduleOverdueToToday(c.now());
    notifyDataChanged(c);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${before.length} tarefa${before.length == 1 ? '' : 's'} reagendada${before.length == 1 ? '' : 's'} para hoje',
        ),
        action: SnackBarAction(
          label: 'Desfazer',
          onPressed: () async {
            await repo.restoreAll(before);
            notifyDataChanged(c);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final data = ref.watch(todayProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('HOJE'),
        actions: [
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: () => context.push('/busca')),
        ],
      ),
      body: AsyncView(data, builder: (d) => _body(context, d.$1, d.$2, now)),
    );
  }

  Widget _body(BuildContext context, TodayView v, TaskListData data, DateTime now) {
    final c = context.colors;
    final children = <Widget>[
      _Header(view: v, now: now),
      if (v.isEmpty)
        const EmptyState(
          icon: Icons.wb_sunny_outlined,
          title: 'Dia livre',
          message: 'Nada marcado para hoje. Toque em + para adicionar uma tarefa ou um evento.',
        ),
      if (v.overdue.isNotEmpty) ...[
        SectionTitle(
          'Atrasadas (${v.overdue.length})',
          trailing: TextButton.icon(
            onPressed: _rescheduleAll,
            icon: const Icon(Icons.update, size: 18),
            label: const Text('Reagendar tudo para hoje'),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: c.error.withValues(alpha: 0.6)),
            color: c.error.withValues(alpha: 0.06),
          ),
          padding: const EdgeInsets.all(4),
          child: Column(
            children: [
              for (final t in v.overdue)
                _gap(TaskTile(key: ValueKey('o${t.id}'), task: t, progress: data.progressOf(t))),
            ],
          ),
        ),
      ],
      if (v.allDayEvents.isNotEmpty || v.timeline.isNotEmpty) ...[
        const SectionTitle('Linha do tempo'),
        for (final e in v.allDayEvents) _gap(EventTile(e)),
        for (final e in v.timeline)
          _gap(
            _TimelineRow(
              time: hm(e.sortKey),
              past: e.sortKey.isBefore(now),
              child: e.event != null
                  ? EventTile(e.event!)
                  : TaskTile(
                      key: ValueKey('t${e.task!.id}'),
                      task: e.task!,
                      progress: data.progressOf(e.task!),
                      showDue: false,
                    ),
            ),
          ),
      ],
      if (v.untimed.isNotEmpty) ...[
        const SectionTitle('Tarefas de hoje'),
        for (final t in v.untimed)
          _gap(TaskTile(key: ValueKey('u${t.id}'), task: t, progress: data.progressOf(t), showDue: false)),
      ],
      if (v.pinned.isNotEmpty) ...[
        const SectionTitle('Fixadas para hoje'),
        for (final t in v.pinned) _gap(TaskTile(key: ValueKey('p${t.id}'), task: t, progress: data.progressOf(t))),
      ],
      if (v.completedToday.isNotEmpty) ...[
        SectionTitle(
          'Concluídas hoje (${v.completedToday.length})',
          trailing: TextButton(
            onPressed: () => setState(() => _showDone = !_showDone),
            child: Text(_showDone ? 'Recolher' : 'Mostrar'),
          ),
        ),
        AnimatedSize(
          duration: shortAnimation,
          alignment: Alignment.topCenter,
          child: _showDone
              ? Column(
                  children: [
                    for (final t in v.completedToday)
                      _gap(
                        TaskTile(key: ValueKey('d${t.id}'), task: t, progress: data.progressOf(t), swipeActions: false),
                      ),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    ];
    return RefreshIndicator(
      onRefresh: () async => ref.dataChanged(),
      child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: children),
    );
  }

  Widget _gap(Widget w) => Padding(padding: const EdgeInsets.only(bottom: 8), child: w);
}

class _Header extends StatelessWidget {
  const _Header({required this.view, required this.now});
  final TodayView view;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final counter = '${view.doneCount} de ${view.totalCount} concluída${view.totalCount == 1 ? '' : 's'}';
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(longDate(now), style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 6),
                Text(
                  counter,
                  style: TextStyle(color: c.textSecondary, fontFeatures: tabular),
                ),
                if (view.eventCount > 0)
                  Text(
                    '${view.eventCount} evento${view.eventCount == 1 ? '' : 's'} hoje',
                    style: TextStyle(color: c.textSecondary, fontFeatures: tabular),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ProgressRing(
            value: view.progress,
            label: '${(view.progress * 100).round()}%',
            semanticsLabel: 'Progresso do dia: $counter',
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.time, required this.child, required this.past});
  final String time;
  final Widget child;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 52,
          child: Text(
            time,
            style: TextStyle(
              fontFeatures: tabular,
              fontWeight: FontWeight.w600,
              color: past ? c.textSecondary : c.text,
            ),
          ),
        ),
        Expanded(child: child),
      ],
    );
  }
}
