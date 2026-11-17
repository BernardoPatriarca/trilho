// Detalhe/edição de tarefa: título, descrição, prazo (data e hora opcionais),
// prioridade (4 chips), categoria, tags, recorrência, lembretes, "fixar em
// Hoje" e a checklist. Marcar itens já salvos grava na hora (lista do mercado
// no meio do corredor); o resto grava em "Salvar".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/form_fields.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/priority.dart';
import 'checklist_editor.dart';
import 'task_actions.dart';
import 'task_repository.dart';

class TaskEditPage extends ConsumerStatefulWidget {
  const TaskEditPage({super.key, this.taskId, this.initial});
  final int? taskId;

  /// Rascunho vindo da adição rápida ("Mais detalhes").
  final TaskDraft? initial;

  @override
  ConsumerState<TaskEditPage> createState() => _TaskEditPageState();
}

class _TaskEditPageState extends ConsumerState<TaskEditPage> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  Task? _original;
  int _priority = 4;
  DateTime? _date;
  int? _minutes;
  int? _categoryId;
  List<String> _tags = [];
  RecurrenceRule? _rule;
  List<Reminder> _reminders = [];
  bool _remindersTouched = false;
  bool _pinned = false;
  final List<EditableItem> _items = [];

  bool get _isNew => _original?.id == null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.taskId != null) {
      final d = await ref.read(taskRepositoryProvider).get(widget.taskId!);
      if (d != null) {
        _original = d.task;
        _apply(d.task, d.checklist, d.tags.map((t) => t.name).toList(), d.reminders, d.rule);
        _remindersTouched = true;
      }
    } else if (widget.initial != null) {
      final i = widget.initial!;
      _original = i.task;
      _apply(i.task, i.checklist, i.tagNames, i.reminders, i.rule);
      _remindersTouched = i.remindersTouched;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _apply(Task t, List<ChecklistItem> items, List<String> tags, List<Reminder> rem, RecurrenceRule? rule) {
    _title.text = t.title;
    _desc.text = t.description ?? '';
    _priority = t.priority;
    _date = t.dueDate;
    _minutes = t.dueMinutes;
    _categoryId = t.categoryId;
    _tags = [...tags];
    _rule = rule;
    _reminders = [...rem];
    _pinned = t.pinnedToday;
    _items
      ..clear()
      ..addAll([...items.where((i) => !i.checked), ...items.where((i) => i.checked)].map(EditableItem.from));
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  void _touch(VoidCallback f) => setState(() {
    f();
    _dirty = true;
    _error = null;
  });

  TaskDraft _draft() {
    final now = ref.now();
    final base = _original ?? Task(title: '', createdAt: now, updatedAt: now);
    return TaskDraft(
      task: base.copyWith(
        title: _title.text,
        description: _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        clearDescription: _desc.text.trim().isEmpty,
        priority: _priority,
        dueDate: _date,
        clearDue: _date == null,
        dueMinutes: _minutes,
        clearTime: _minutes == null,
        categoryId: _categoryId,
        clearCategory: _categoryId == null,
        pinnedToday: _pinned,
      ),
      checklist: [for (final (i, it) in _items.indexed) it.toItem(i)],
      tagNames: _tags,
      reminders: _reminders,
      rule: _rule,
      remindersTouched: _remindersTouched,
    );
  }

  Future<int?> _save({bool pop = true}) async {
    setState(() => _saving = true);
    try {
      final id = await ref.read(taskRepositoryProvider).save(_draft(), now: ref.now());
      ref.dataChanged();
      _dirty = false;
      if (pop && mounted) context.pop();
      return id;
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _onToggle(EditableItem it) async {
    // Item já salvo numa tarefa existente: grava na hora.
    if (!_isNew && it.id != null) {
      final p = await ref.read(taskRepositoryProvider).setItemChecked(it.id!, it.checked);
      ref.dataChanged();
      if (p.allChecked && (_original?.isPending ?? false) && mounted) {
        final ok = await confirm(
          context,
          title: 'Concluir a tarefa também?',
          message: 'Todos os itens da checklist estão marcados.',
          confirmLabel: 'Concluir',
        );
        if (ok && mounted) {
          if (_dirty) await _save(pop: false);
          if (!mounted) return;
          final t = (await ref.read(taskRepositoryProvider).get(_original!.id!))!.task;
          if (!mounted) return;
          await completeTask(context, t);
          if (mounted) context.pop();
        }
      }
    } else {
      setState(() => _dirty = true);
    }
  }

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    return confirm(
      context,
      title: 'Descartar alterações?',
      message: 'As mudanças não salvas serão perdidas.',
      confirmLabel: 'Descartar',
      destructive: true,
    );
  }

  Future<void> _menu(String action) async {
    final t = _original;
    if (t == null || t.id == null) return;
    switch (action) {
      case 'concluir':
        if (_dirty) await _save(pop: false);
        final fresh = (await ref.read(taskRepositoryProvider).get(t.id!))!.task;
        if (!mounted) return;
        await completeTask(context, fresh);
        if (mounted) context.pop();
      case 'reabrir':
        await reopenTask(context, t);
        if (mounted) context.pop();
      case 'adiar':
        await showPostponeSheet(context, t);
        if (mounted) context.pop();
      case 'cancelar':
        await ref.read(taskRepositoryProvider).cancel(t.id!, ref.now());
        ref.dataChanged();
        if (mounted) context.pop();
      case 'excluir':
        if (await deleteTask(context, t) && mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (widget.taskId != null && _original == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: Icons.search_off,
          title: 'Tarefa não encontrada',
          message: 'Ela pode ter sido excluída.',
        ),
      );
    }
    final o = _original;
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          _dirty = false;
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'NOVA TAREFA' : 'TAREFA'),
          actions: [
            if (!_isNew)
              PopupMenuButton<String>(
                tooltip: 'Mais ações',
                onSelected: _menu,
                itemBuilder: (_) => [
                  if (o!.isPending) const PopupMenuItem(value: 'concluir', child: Text('Concluir')),
                  if (!o.isPending) const PopupMenuItem(value: 'reabrir', child: Text('Reabrir')),
                  if (o.isPending) const PopupMenuItem(value: 'adiar', child: Text('Adiar…')),
                  if (o.isPending) const PopupMenuItem(value: 'cancelar', child: Text('Cancelar tarefa')),
                  const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            TextField(
              key: const Key('taskTitle'),
              controller: _title,
              autofocus: _isNew && _title.text.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(labelText: 'Título'),
              onChanged: (_) => _touch(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              minLines: 2,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Descrição', alignLabelWithHint: true),
              onChanged: (_) => _touch(() {}),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: c.error, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_error!, style: TextStyle(color: c.error)),
                    ),
                  ],
                ),
              ),
            const SectionTitle('Prazo'),
            Row(
              children: [
                Expanded(
                  child: FieldButton(
                    label: 'Data',
                    icon: Icons.event_outlined,
                    value: _date == null ? 'Sem prazo' : dayMonthYear(_date!),
                    onTap: () async {
                      final d = await pickDate(context, _date);
                      if (d != null) _touch(() => _date = d);
                    },
                    onClear: _date == null
                        ? null
                        : () => _touch(() {
                            _date = null;
                            _minutes = null;
                            _rule = null;
                          }),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FieldButton(
                    label: 'Hora',
                    icon: Icons.schedule,
                    value: _minutes == null ? 'Sem hora' : minutesToHm(_minutes!),
                    onTap: () async {
                      if (_date == null) {
                        setState(() => _error = 'A hora do prazo precisa de uma data.');
                        return;
                      }
                      final m = await pickTime(context, _minutes);
                      if (m != null) _touch(() => _minutes = m);
                    },
                    onClear: _minutes == null ? null : () => _touch(() => _minutes = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            RecurrenceField(
              rule: _rule,
              start: _date,
              enabled: _date != null,
              onChanged: (r) => _touch(() => _rule = r),
            ),
            const SectionTitle('Prioridade'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in Priority.values)
                  ChoiceChip(
                    avatar: CircleAvatar(backgroundColor: priorityColor(p), radius: 6),
                    label: Text('${p.code} ${p.label}'),
                    selected: _priority == p.value,
                    onSelected: (_) => _touch(() => _priority = p.value),
                  ),
              ],
            ),
            const SectionTitle('Categoria'),
            CategoryPicker(value: _categoryId, onChanged: (id) => _touch(() => _categoryId = id)),
            const SectionTitle('Tags'),
            TagsField(tags: _tags, onChanged: (t) => _touch(() => _tags = t)),
            const SectionTitle('Lembretes'),
            if (_date == null)
              Text(
                'Defina um prazo para receber lembretes relativos.',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
            RemindersEditor(
              reminders: _reminders,
              relativeTo: 'antes do prazo',
              onChanged: (r) => _touch(() {
                _reminders = r;
                _remindersTouched = true;
              }),
            ),
            if (_isNew && !_remindersTouched && _date != null && _reminders.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _minutes == null ? 'Padrão: lembrete às 9h do dia do prazo.' : 'Padrão: lembrete na hora do prazo.',
                  style: TextStyle(fontSize: 12, color: c.textSecondary),
                ),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Fixar em Hoje'),
              subtitle: const Text('Aparece na tela Hoje sem mudar o prazo'),
              value: _pinned,
              onChanged: (v) => _touch(() => _pinned = v),
            ),
            ChecklistEditor(items: _items, onChanged: () => setState(() => _dirty = true), onToggle: _onToggle),
            if (o != null && o.id != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 8),
              DefaultTextStyle(
                style: TextStyle(fontFamily: bodyFont, fontSize: 12, color: c.textSecondary, fontFeatures: tabular),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Criada em ${dayMonthYear(o.createdAt)} às ${hm(o.createdAt)}'),
                    if (o.completedAt != null)
                      Text('Concluída em ${dayMonthYear(o.completedAt!)} às ${hm(o.completedAt!)}'),
                    Text('Adiamentos: ${o.postponements}'),
                    if (o.status == TaskStatus.cancelada) const Text('Status: cancelada'),
                  ],
                ),
              ),
            ],
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 8 + MediaQuery.viewInsetsOf(context).bottom * 0),
            child: FilledButton.icon(
              key: const Key('taskSave'),
              onPressed: _saving ? null : () => _save(),
              icon: const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ),
        ),
      ),
    );
  }
}
