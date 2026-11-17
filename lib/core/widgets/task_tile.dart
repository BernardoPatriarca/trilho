// Item de tarefa das listas: caixa para concluir (risco animado no texto +
// vibração leve), prioridade com rótulo, categoria, prazo e checklist.
// Arrastar para a direita conclui; para a esquerda, adia (com desfazer).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/priority.dart';
import '../../domain/tasks.dart';
import '../../features/tasks/task_actions.dart';
import '../data_providers.dart';
import '../providers.dart';
import 'common.dart';

/// "Hoje 18:00", "Amanhã", "seg, 23/11", "15/11/2025".
String dueLabel(Task t, DateTime now) {
  if (t.dueDate == null) return '';
  final d = t.dueDate!;
  final diff = daysBetween(dateOnly(now), d);
  final time = t.dueMinutes == null ? '' : ' ${minutesToHm(t.dueMinutes!)}';
  final day = switch (diff) {
    0 => 'Hoje',
    1 => 'Amanhã',
    -1 => 'Ontem',
    _ when diff > 1 && diff < 7 => '${weekdayShort[d.weekday]}, ${dayMonth(d)}',
    _ when d.year == now.year => dayMonth(d),
    _ => dayMonthYear(d),
  };
  return '$day$time';
}

class TaskTile extends ConsumerStatefulWidget {
  const TaskTile({
    super.key,
    required this.task,
    this.progress = ChecklistProgress.empty,
    this.swipeActions = true,
    this.highlight,
    this.showDue = true,
    this.dragHandle,
  });

  final Task task;
  final ChecklistProgress progress;
  final bool swipeActions;
  final String? highlight;
  final bool showDue;
  final Widget? dragHandle;

  @override
  ConsumerState<TaskTile> createState() => _TaskTileState();
}

class _TaskTileState extends ConsumerState<TaskTile> {
  bool _completing = false;

  Future<void> _toggle() async {
    final t = widget.task;
    if (t.isDone) {
      await reopenTask(context, t);
      return;
    }
    setState(() => _completing = true);
    // Deixa o risco animar antes de a tarefa mudar de seção.
    await Future<void>.delayed(shortAnimation);
    if (!mounted) return;
    await completeTask(context, t);
    if (mounted) setState(() => _completing = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final c = context.colors;
    final now = ref.watch(clockProvider)();
    final category = ref.watch(categoryMapProvider)[t.categoryId];
    final done = t.isDone || _completing;
    final overdue = isOverdue(t, now);
    final priority = Priority.fromValue(t.priority);
    final due = widget.showDue ? dueLabel(t, now) : '';

    final semantics = [
      t.title,
      if (t.isDone) 'concluída',
      'prioridade ${priority.label}',
      if (due.isNotEmpty) 'prazo $due',
      if (overdue) 'atrasada',
      if (category != null) 'categoria ${category.name}',
      if (!widget.progress.isEmpty) 'checklist ${widget.progress.checked} de ${widget.progress.total}',
    ].join(', ');

    final tile = Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/tarefa/${t.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                button: true,
                checked: done,
                label: done ? 'Reabrir ${t.title}' : 'Concluir ${t.title}',
                excludeSemantics: true,
                child: InkResponse(
                  key: Key('check-${t.id}'),
                  onTap: _toggle,
                  radius: 24,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: AnimatedContainer(
                        duration: shortAnimation,
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? c.accent : Colors.transparent,
                          border: Border.all(color: done ? c.accent : priorityColor(priority), width: 2),
                        ),
                        child: done ? Icon(Icons.check, size: 16, color: c.onAccent) : null,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Semantics(
                  label: semantics,
                  excludeSemantics: true,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _StrikeText(
                        text: t.title,
                        struck: done,
                        highlight: widget.highlight,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: done ? c.textSecondary : c.text,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (t.priority < 4) PriorityBadge(priority, compact: true),
                          if (due.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  overdue ? Icons.warning_amber_rounded : Icons.event_outlined,
                                  size: 14,
                                  color: overdue ? c.error : c.textSecondary,
                                ),
                                const SizedBox(width: 3),
                                Flexible(
                                  child: Text(
                                    overdue ? 'Atrasada · $due' : due,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: overdue ? c.error : c.textSecondary,
                                      fontFeatures: tabular,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          if (t.isRecurring)
                            Icon(Icons.repeat, size: 14, color: c.textSecondary, semanticLabel: 'recorrente'),
                          if (t.pinnedToday)
                            Icon(
                              Icons.push_pin_outlined,
                              size: 14,
                              color: c.textSecondary,
                              semanticLabel: 'fixada em hoje',
                            ),
                          if (category != null) CategoryBadge(category, dense: true),
                        ],
                      ),
                      if (!widget.progress.isEmpty) ...[const SizedBox(height: 6), ChecklistBar(widget.progress)],
                    ],
                  ),
                ),
              ),
              ?widget.dragHandle,
            ],
          ),
        ),
      ),
    );

    if (!widget.swipeActions || t.isDone || !t.isPending) return tile;
    return Dismissible(
      key: ValueKey('swipe-${t.id}'),
      background: _SwipeBg(icon: Icons.check, label: 'Concluir', color: c.success, alignStart: true),
      secondaryBackground: _SwipeBg(icon: Icons.schedule, label: 'Adiar', color: c.warning, alignStart: false),
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await completeTask(context, t);
        } else {
          await postponeDefault(context, t);
        }
        // O item volta e a lista recarrega já com a mudança.
        return false;
      },
      child: tile,
    );
  }
}

class _SwipeBg extends StatelessWidget {
  const _SwipeBg({required this.icon, required this.label, required this.color, required this.alignStart});
  final IconData icon;
  final String label;
  final Color color;
  final bool alignStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: color.withValues(alpha: 0.25), borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignStart ? Alignment.centerLeft : Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: context.colors.text),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: context.colors.text, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Texto com um risco que cresce da esquerda para a direita.
class _StrikeText extends StatelessWidget {
  const _StrikeText({required this.text, required this.struck, required this.style, this.highlight});
  final String text;
  final bool struck;
  final TextStyle style;
  final String? highlight;

  @override
  Widget build(BuildContext context) {
    final content = highlight == null || highlight!.isEmpty
        ? Text(text, style: style, maxLines: 2, overflow: TextOverflow.ellipsis)
        : HighlightText(text, highlight!, style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: struck ? 1 : 0, end: struck ? 1 : 0),
      duration: shortAnimation,
      builder: (context, v, child) =>
          CustomPaint(foregroundPainter: _StrikePainter(v, style.color ?? context.colors.text), child: child),
      child: content,
    );
  }
}

class _StrikePainter extends CustomPainter {
  _StrikePainter(this.progress, this.color);
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final y = size.height / 2;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width * progress, y),
      Paint()
        ..color = color
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_StrikePainter old) => old.progress != progress || old.color != color;
}
