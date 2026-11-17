// Adição rápida (regra 6.7): bottom sheet com o campo de texto, chips do que
// foi reconhecido ao vivo (toque no chip para desfazer o reconhecimento),
// seletor Tarefa/Evento e "Mais detalhes" (formulário completo preenchido).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/quick_add_parser.dart';
import '../events/event_repository.dart';
import '../tasks/task_repository.dart';

enum QuickAddKind { task, event }

Future<void> showQuickAddSheet(BuildContext context, {QuickAddKind kind = QuickAddKind.task}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => QuickAddSheet(initialKind: kind),
  );
}

class QuickAddSheet extends ConsumerStatefulWidget {
  const QuickAddSheet({super.key, this.initialKind = QuickAddKind.task});
  final QuickAddKind initialKind;

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  final _text = TextEditingController();
  late QuickAddKind _kind = widget.initialKind;

  /// O usuário mexeu no seletor (aí a palavra "evento" não decide sozinha).
  bool _kindTouched = false;
  final Set<String> _ignored = {};
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  QuickAddResult _parse() {
    final cats = (ref.read(categoriesProvider).value ?? const <Category>[]).where((c) => c.active).toList();
    return parseQuickAdd(_text.text, ref.now(), categories: cats, ignored: _ignored);
  }

  QuickAddKind _effectiveKind(QuickAddResult r) => _kindTouched ? _kind : (r.isEvent ? QuickAddKind.event : _kind);

  (TaskDraft?, EventDraft?) _drafts(QuickAddResult r) {
    final now = ref.now();
    if (_effectiveKind(r) == QuickAddKind.task) {
      return (
        TaskDraft(
          task: Task(
            title: r.title,
            dueDate: r.date,
            dueMinutes: r.minutes,
            priority: r.priority ?? 4,
            categoryId: r.categoryId,
            createdAt: now,
            updatedAt: now,
          ),
          tagNames: r.tags,
          rule: r.rule,
        ),
        null,
      );
    }
    final day = r.date ?? dateOnly(now);
    final allDay = r.minutes == null;
    final start = allDay ? day : atMinutes(day, r.minutes!);
    return (
      null,
      EventDraft(
        event: Event(
          title: r.title,
          start: start,
          end: allDay ? day : start.add(const Duration(hours: 1)),
          allDay: allDay,
          categoryId: r.categoryId,
          createdAt: now,
          updatedAt: now,
        ),
        tagNames: r.tags,
        rule: r.rule,
      ),
    );
  }

  Future<void> _save() async {
    final r = _parse();
    if (r.title.trim().isEmpty) {
      setState(() => _error = 'Escreva o que é (o título fica com o que sobra).');
      return;
    }
    setState(() => _saving = true);
    final (task, event) = _drafts(r);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      String route;
      String label;
      if (task != null) {
        final id = await ref.read(taskRepositoryProvider).save(task, now: ref.now());
        route = '/tarefa/$id';
        label = 'Tarefa criada';
      } else {
        final cfg = await ref.read(configProvider.future);
        final id = await ref
            .read(eventRepositoryProvider)
            .save(event!, now: ref.now(), defaultReminderMin: cfg.defaultEventReminder);
        route = '/evento/$id';
        label = 'Evento criado';
      }
      ref.dataChanged();
      if (!mounted) return;
      Navigator.pop(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$label: ${r.title}'),
          action: SnackBarAction(label: 'Abrir', onPressed: () => router.push(route)),
        ),
      );
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _moreDetails() {
    final r = _parse();
    final (task, event) = _drafts(r);
    final router = GoRouter.of(context);
    Navigator.pop(context);
    if (task != null) {
      router.push('/tarefa/nova', extra: task);
    } else {
      router.push('/evento/novo', extra: event);
    }
  }

  IconData _icon(TokenKind k) => switch (k) {
    TokenKind.date => Icons.event_outlined,
    TokenKind.time => Icons.schedule,
    TokenKind.recurrence => Icons.repeat,
    TokenKind.category => Icons.folder_outlined,
    TokenKind.tag => Icons.tag,
    TokenKind.priority => Icons.flag_outlined,
    TokenKind.event => Icons.event_available_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    ref.watch(categoriesProvider);
    final r = _parse();
    final kind = _effectiveKind(r);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ADIÇÃO RÁPIDA', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              key: const Key('quickAddField'),
              controller: _text,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(hintText: 'Mercado amanhã 18h #casa !2 @compras', errorText: _error),
              onChanged: (_) => setState(() {
                _error = null;
                // Chips removidos que sumiram do texto deixam de valer.
                _ignored.removeWhere((raw) => !_text.text.contains(raw));
              }),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            AnimatedSize(
              duration: shortAnimation,
              alignment: Alignment.topLeft,
              child: r.tokens.isEmpty && _ignored.isEmpty
                  ? Text(
                      'Reconhece datas, horas, "toda segunda", @categoria, #tag e !1 a !4.',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final t in r.tokens)
                          InputChip(
                            key: Key('chip-${t.kind.name}'),
                            avatar: Icon(_icon(t.kind), size: 16),
                            label: Text(t.label),
                            onDeleted: () => setState(() => _ignored.add(t.raw)),
                            deleteButtonTooltipMessage: 'Não reconhecer "${t.raw}"',
                          ),
                        for (final raw in _ignored)
                          ActionChip(
                            avatar: const Icon(Icons.undo, size: 16),
                            label: Text('"$raw" no título'),
                            onPressed: () => setState(() => _ignored.remove(raw)),
                          ),
                      ],
                    ),
            ),
            if (r.title.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: 'Título: ',
                      style: TextStyle(color: c.textSecondary),
                    ),
                    TextSpan(
                      text: r.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<QuickAddKind>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: QuickAddKind.task, icon: Icon(Icons.check_circle_outline), label: Text('Tarefa')),
                ButtonSegment(value: QuickAddKind.event, icon: Icon(Icons.event_outlined), label: Text('Evento')),
              ],
              selected: {kind},
              onSelectionChanged: (s) => setState(() {
                _kind = s.first;
                _kindTouched = true;
              }),
            ),
            if (kind == QuickAddKind.event)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  r.minutes == null ? 'Sem horário: evento de dia inteiro.' : 'Evento de 1 hora.',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(onPressed: _moreDetails, child: const Text('Mais detalhes')),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const Key('quickAddSave'),
                    onPressed: _saving ? null : _save,
                    child: const Text('Adicionar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
