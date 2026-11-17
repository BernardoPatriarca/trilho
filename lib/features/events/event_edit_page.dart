// Criar/editar evento. Em evento recorrente, salvar ou excluir pergunta:
// "Só este evento", "Este e os seguintes" ou "Todos".
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/form_fields.dart';
import '../../domain/dates.dart';
import '../../domain/event_expansion.dart';
import '../../domain/models.dart';
import '../tasks/task_repository.dart';
import 'event_repository.dart';

Future<EditScope?> askScope(BuildContext context, {required bool deleting}) => showDialog<EditScope>(
  context: context,
  builder: (ctx) => SimpleDialog(
    title: Text(deleting ? 'Excluir evento recorrente' : 'Salvar evento recorrente'),
    children: [
      for (final s in EditScope.values)
        SimpleDialogOption(
          onPressed: () => Navigator.pop(ctx, s),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(s.label, style: const TextStyle(fontSize: 16)),
          ),
        ),
    ],
  ),
);

class EventEditPage extends ConsumerStatefulWidget {
  const EventEditPage({super.key, this.eventId, this.occurrenceDate, this.initial, this.initialStart});
  final int? eventId;
  final DateTime? occurrenceDate;
  final EventDraft? initial;

  /// Toque longo na grade de horários: já vem com o horário escolhido.
  final DateTime? initialStart;

  @override
  ConsumerState<EventEditPage> createState() => _EventEditPageState();
}

class _EventEditPageState extends ConsumerState<EventEditPage> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _local = TextEditingController();
  bool _loading = true;
  bool _dirty = false;
  bool _saving = false;
  String? _error;

  Event? _original;
  EventOccurrence? _occurrence;
  late DateTime _start;
  late DateTime _end;
  bool _allDay = false;
  int? _categoryId;
  List<String> _tags = [];
  RecurrenceRule? _rule;
  List<Reminder> _reminders = [];
  bool _remindersTouched = false;

  bool get _isNew => _original?.id == null;
  bool get _isRecurringExisting => !_isNew && _original!.isRecurring && _occurrence != null;

  @override
  void initState() {
    super.initState();
    final now = ref.read(clockProvider)();
    final s = widget.initialStart ?? atMinutes(dateOnly(now), ((now.hour + 1) % 24) * 60);
    _start = s;
    _end = s.add(const Duration(hours: 1));
    _load();
  }

  Future<void> _load() async {
    if (widget.eventId != null) {
      final d = await ref.read(eventRepositoryProvider).get(widget.eventId!);
      if (d != null) {
        _original = d.event;
        _fill(d.event, d.tags.map((t) => t.name).toList(), d.reminders, d.rule);
        _remindersTouched = true;
        if (d.event.isRecurring) {
          final day = widget.occurrenceDate ?? d.event.start;
          final occ = expandEvents(
            [EventSeries(d.event, rule: d.rule, exceptions: d.exceptions)],
            day,
            day,
          ).where((o) => isSameDay(o.occurrenceDate, day)).firstOrNull;
          if (occ != null) {
            _occurrence = occ;
            _start = occ.start;
            _end = occ.end;
            _title.text = occ.title;
          }
        }
      }
    } else if (widget.initial != null) {
      final i = widget.initial!;
      _original = i.event;
      _fill(i.event, i.tagNames, i.reminders, i.rule);
      _remindersTouched = i.remindersTouched;
    }
    if (mounted) setState(() => _loading = false);
  }

  void _fill(Event e, List<String> tags, List<Reminder> rem, RecurrenceRule? rule) {
    _title.text = e.title;
    _desc.text = e.description ?? '';
    _local.text = e.location ?? '';
    _start = e.start;
    _end = e.end;
    _allDay = e.allDay;
    _categoryId = e.categoryId;
    _tags = [...tags];
    _reminders = [...rem];
    _rule = rule;
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _local.dispose();
    super.dispose();
  }

  void _touch(VoidCallback f) => setState(() {
    f();
    _dirty = true;
    _error = null;
  });

  EventDraft _draft() {
    final now = ref.now();
    final base = _original ?? Event(title: '', start: _start, end: _end, createdAt: now, updatedAt: now);
    String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return EventDraft(
      event: base.copyWith(
        title: _title.text,
        description: opt(_desc),
        clearDescription: opt(_desc) == null,
        location: opt(_local),
        clearLocation: opt(_local) == null,
        start: _allDay ? dateOnly(_start) : _start,
        end: _allDay ? dateOnly(_end) : _end,
        allDay: _allDay,
        categoryId: _categoryId,
        clearCategory: _categoryId == null,
      ),
      rule: _rule,
      tagNames: _tags,
      reminders: _reminders,
      remindersTouched: _remindersTouched,
    );
  }

  Future<void> _save() async {
    final repo = ref.read(eventRepositoryProvider);
    final cfg = await ref.read(configProvider.future);
    EditScope? scope;
    if (_isRecurringExisting) {
      if (!mounted) return;
      scope = await askScope(context, deleting: false);
      if (scope == null) return;
    }
    setState(() => _saving = true);
    try {
      if (scope != null) {
        await repo.saveOccurrence(
          scope,
          _occurrence!,
          _draft(),
          now: ref.now(),
          defaultReminderMin: cfg.defaultEventReminder,
        );
      } else {
        await repo.save(_draft(), now: ref.now(), defaultReminderMin: cfg.defaultEventReminder);
      }
      ref.dataChanged();
      _dirty = false;
      if (mounted) context.pop();
    } on ValidationException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final repo = ref.read(eventRepositoryProvider);
    if (_isRecurringExisting) {
      final scope = await askScope(context, deleting: true);
      if (scope == null) return;
      await repo.deleteOccurrence(scope, _occurrence!, now: ref.now());
    } else {
      final ok = await confirm(
        context,
        title: 'Excluir evento?',
        message: '"${_original!.title}" será apagado.',
        confirmLabel: 'Excluir',
        destructive: true,
      );
      if (!ok) return;
      await repo.delete(_original!.id!);
    }
    ref.dataChanged();
    _dirty = false;
    if (mounted) context.pop();
  }

  Future<void> _pickStartDate() async {
    final d = await pickDate(context, _start);
    if (d == null) return;
    final dur = _end.difference(_start);
    _touch(() {
      _start = _allDay ? d : atMinutes(d, minutesOfDay(_start));
      // O fim acompanha o início (mantém a duração).
      _end = _start.add(dur);
    });
  }

  Future<void> _pickStartTime() async {
    final m = await pickTime(context, minutesOfDay(_start));
    if (m == null) return;
    final dur = _end.difference(_start);
    _touch(() {
      _start = atMinutes(_start, m);
      _end = _start.add(dur);
    });
  }

  Future<void> _pickEndDate() async {
    final d = await pickDate(context, _end, first: dateOnly(_start));
    if (d == null) return;
    _touch(() => _end = _allDay ? d : atMinutes(d, minutesOfDay(_end)));
  }

  Future<void> _pickEndTime() async {
    final m = await pickTime(context, minutesOfDay(_end));
    if (m == null) return;
    _touch(() {
      _end = atMinutes(_end, m);
      // Fim antes do início no mesmo dia: provavelmente passa da meia-noite.
      if (!_end.isAfter(_start) && isSameDay(_end, _start)) _end = addDays(_end, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (widget.eventId != null && _original == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.search_off, title: 'Evento não encontrado'),
      );
    }
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await confirm(context, title: 'Descartar alterações?', confirmLabel: 'Descartar', destructive: true);
        if (ok && context.mounted) {
          _dirty = false;
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? 'NOVO EVENTO' : 'EVENTO'),
          actions: [
            if (!_isNew) IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline), onPressed: _delete),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
          children: [
            if (_isRecurringExisting)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Icon(Icons.repeat, size: 18, color: c.textSecondary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Ocorrência de ${dayMonthYear(_occurrence!.occurrenceDate)} de um evento recorrente',
                        style: TextStyle(color: c.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              key: const Key('eventTitle'),
              controller: _title,
              autofocus: _isNew && _title.text.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
              decoration: const InputDecoration(labelText: 'Título'),
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
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dia inteiro'),
              value: _allDay,
              onChanged: (v) => _touch(() {
                _allDay = v;
                if (v) {
                  _start = dateOnly(_start);
                  _end = dateOnly(_end);
                } else {
                  _start = atMinutes(_start, 9 * 60);
                  _end = isSameDay(_start, _end) ? _start.add(const Duration(hours: 1)) : atMinutes(_end, 10 * 60);
                }
              }),
            ),
            const SectionTitle('Início'),
            Row(
              children: [
                Expanded(
                  child: FieldButton(
                    label: 'Data',
                    icon: Icons.event_outlined,
                    value: dayMonthYear(_start),
                    onTap: _pickStartDate,
                  ),
                ),
                if (!_allDay) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FieldButton(label: 'Hora', icon: Icons.schedule, value: hm(_start), onTap: _pickStartTime),
                  ),
                ],
              ],
            ),
            const SectionTitle('Fim'),
            Row(
              children: [
                Expanded(
                  child: FieldButton(
                    label: 'Data',
                    icon: Icons.event_outlined,
                    value: dayMonthYear(_end),
                    onTap: _pickEndDate,
                  ),
                ),
                if (!_allDay) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: FieldButton(label: 'Hora', icon: Icons.schedule, value: hm(_end), onTap: _pickEndTime),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            RecurrenceField(rule: _rule, start: _start, onChanged: (r) => _touch(() => _rule = r)),
            const SizedBox(height: 12),
            TextField(
              controller: _local,
              decoration: const InputDecoration(labelText: 'Local', prefixIcon: Icon(Icons.place_outlined)),
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
            const SectionTitle('Categoria'),
            CategoryPicker(value: _categoryId, onChanged: (id) => _touch(() => _categoryId = id)),
            const SectionTitle('Tags'),
            TagsField(tags: _tags, onChanged: (t) => _touch(() => _tags = t)),
            const SectionTitle('Lembretes'),
            RemindersEditor(
              reminders: _reminders,
              relativeTo: 'antes do início',
              onChanged: (r) => _touch(() {
                _reminders = r;
                _remindersTouched = true;
              }),
            ),
            if (_isNew && !_remindersTouched && _reminders.isEmpty)
              Consumer(
                builder: (context, ref, _) {
                  final m = ref.watch(configProvider).value?.defaultEventReminder ?? 15;
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Padrão: lembrete $m min antes.',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                    ),
                  );
                },
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: FilledButton.icon(
              key: const Key('eventSave'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.check),
              label: const Text('Salvar'),
            ),
          ),
        ),
      ),
    );
  }
}
