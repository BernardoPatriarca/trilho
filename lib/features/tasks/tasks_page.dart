// Aba Tarefas: filtros (Todas, Hoje, Próximos 7 dias, Sem prazo, Atrasadas,
// Concluídas), agrupamento por categoria ou prazo e ordem manual (arrastar).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/task_tile.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/tasks.dart';
import 'task_repository.dart';

enum TaskFilter {
  todas('Todas'),
  hoje('Hoje'),
  semana('Próximos 7 dias'),
  semPrazo('Sem prazo'),
  atrasadas('Atrasadas'),
  concluidas('Concluídas');

  const TaskFilter(this.label);
  final String label;
}

enum TaskGrouping {
  manual('Ordem manual'),
  prazo('Por prazo'),
  categoria('Por categoria');

  const TaskGrouping(this.label);
  final String label;
}

List<Task> filterTasks(List<Task> all, TaskFilter f, DateTime now) {
  final today = dateOnly(now);
  bool due(Task t, bool Function(DateTime d) test) => t.dueDate != null && test(dateOnly(t.dueDate!));
  return switch (f) {
    TaskFilter.todas => all.where((t) => t.isPending).toList(),
    TaskFilter.hoje => all.where((t) => t.isPending && (due(t, (d) => !d.isAfter(today)) || t.pinnedToday)).toList(),
    TaskFilter.semana =>
      all.where((t) => t.isPending && due(t, (d) => !d.isBefore(today) && d.isBefore(addDays(today, 7)))).toList(),
    TaskFilter.semPrazo => all.where((t) => t.isPending && t.dueDate == null).toList(),
    TaskFilter.atrasadas => all.where((t) => isOverdue(t, now)).toList(),
    TaskFilter.concluidas =>
      (all.where((t) => t.isDone).toList()..sort((a, b) => b.completedAt!.compareTo(a.completedAt!))),
  };
}

class TasksPage extends ConsumerStatefulWidget {
  const TasksPage({super.key});

  @override
  ConsumerState<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends ConsumerState<TasksPage> {
  TaskFilter _filter = TaskFilter.todas;
  TaskGrouping _group = TaskGrouping.prazo;

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(clockProvider)();
    final data = ref.watch(taskListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('TAREFAS'),
        actions: [
          PopupMenuButton<TaskGrouping>(
            tooltip: 'Agrupar',
            icon: const Icon(Icons.sort),
            initialValue: _group,
            onSelected: (g) => setState(() => _group = g),
            itemBuilder: (_) => [for (final g in TaskGrouping.values) PopupMenuItem(value: g, child: Text(g.label))],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _SearchField(onTap: () => context.push('/busca')),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in TaskFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: _filter == f,
                      onSelected: (_) => setState(() => _filter = f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: AsyncView(data, builder: (d) => _list(context, d, now))),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, TaskListData d, DateTime now) {
    final tasks = filterTasks(d.tasks, _filter, now);
    if (tasks.isEmpty) {
      return ListView(
        children: [
          EmptyState(
            icon: _filter == TaskFilter.concluidas ? Icons.emoji_events_outlined : Icons.checklist_rounded,
            title: switch (_filter) {
              TaskFilter.concluidas => 'Nenhuma concluída ainda',
              TaskFilter.atrasadas => 'Nada atrasado',
              TaskFilter.hoje => 'Nada para hoje',
              _ => 'Nenhuma tarefa aqui',
            },
            message: _filter == TaskFilter.atrasadas
                ? 'Tudo no prazo.'
                : 'Toque em + e escreva, por exemplo, "Mercado amanhã 18h".',
          ),
        ],
      );
    }

    if (_filter == TaskFilter.concluidas || _group != TaskGrouping.manual) {
      final groups = _groups(tasks, now);
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          for (final g in groups) ...[
            if (g.$1.isNotEmpty) SectionTitle('${g.$1} (${g.$2.length})'),
            for (final t in g.$2)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TaskTile(key: ValueKey(t.id), task: t, progress: d.progressOf(t), swipeActions: t.isPending),
              ),
          ],
        ],
      );
    }

    // Ordem manual: arrastar pela alça.
    final ordered = [...tasks]..sort((a, b) => a.order.compareTo(b.order));
    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      buildDefaultDragHandles: false,
      itemCount: ordered.length,
      onReorderItem: (from, to) async {
        final ids = ordered.map((t) => t.id!).toList();
        final moved = ids.removeAt(from);
        ids.insert(to, moved);
        await ref.read(taskRepositoryProvider).reorder(ids);
        ref.dataChanged();
      },
      itemBuilder: (context, i) {
        final t = ordered[i];
        return Padding(
          key: ValueKey(t.id),
          padding: const EdgeInsets.only(bottom: 8),
          child: TaskTile(
            task: t,
            progress: d.progressOf(t),
            dragHandle: ReorderableDragStartListener(
              index: i,
              child: Semantics(
                label: 'Arrastar para reordenar',
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle, color: context.colors.textSecondary),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<(String, List<Task>)> _groups(List<Task> tasks, DateTime now) {
    if (_filter == TaskFilter.concluidas) return [('', tasks)];
    if (_group == TaskGrouping.categoria) {
      final cats = ref.read(categoryMapProvider);
      final by = <int?, List<Task>>{};
      for (final t in tasks) {
        by.putIfAbsent(t.categoryId, () => []).add(t);
      }
      final keys = by.keys.toList()
        ..sort((a, b) {
          if (a == null) return 1;
          if (b == null) return -1;
          return (cats[a]?.order ?? 0).compareTo(cats[b]?.order ?? 0);
        });
      return [
        for (final k in keys) (k == null ? 'Sem categoria' : cats[k]?.name ?? 'Categoria', by[k]!..sort(compareByDue)),
      ];
    }
    // Por prazo.
    final today = dateOnly(now);
    final buckets = <String, List<Task>>{};
    for (final t in [...tasks]..sort(compareByDue)) {
      final String key;
      if (t.dueDate == null) {
        key = 'Sem prazo';
      } else if (isOverdue(t, now)) {
        key = 'Atrasadas';
      } else {
        final diff = daysBetween(today, t.dueDate!);
        key = diff == 0
            ? 'Hoje'
            : diff == 1
            ? 'Amanhã'
            : diff < 7
            ? 'Próximos 7 dias'
            : 'Mais tarde';
      }
      buckets.putIfAbsent(key, () => []).add(t);
    }
    const order = ['Atrasadas', 'Hoje', 'Amanhã', 'Próximos 7 dias', 'Mais tarde', 'Sem prazo'];
    return [
      for (final k in order)
        if (buckets[k] != null) (k, buckets[k]!),
    ];
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Buscar tarefas e eventos',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.search, color: c.textSecondary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Buscar tarefas e eventos',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: c.textSecondary),
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

/// Campo de busca reutilizado na Agenda.
class SearchLauncher extends StatelessWidget {
  const SearchLauncher({super.key});
  @override
  Widget build(BuildContext context) => _SearchField(onTap: () => context.push('/busca'));
}
