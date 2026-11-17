// Campos compartilhados pelos formulários de tarefa e evento: data/hora,
// lembretes, categoria, tags e recorrência (com editor amigável).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/recurrence.dart';
import '../../domain/text.dart';
import '../data_providers.dart';
import '../utils/icons.dart';
import 'common.dart';

Future<DateTime?> pickDate(BuildContext context, DateTime? initial, {DateTime? first}) {
  final now = DateTime.now();
  final init = initial ?? dateOnly(now);
  final f = first ?? DateTime(now.year - 5);
  return showDatePicker(
    context: context,
    initialDate: init.isBefore(f) ? f : init,
    firstDate: f,
    lastDate: DateTime(now.year + 10),
  );
}

Future<int?> pickTime(BuildContext context, int? initialMinutes) async {
  final m = initialMinutes ?? 9 * 60;
  final t = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}

/// Botão-campo com rótulo pequeno em cima (data, hora...).
class FieldButton extends StatelessWidget {
  const FieldButton({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
    this.icon,
    this.onClear,
  });
  final String label;
  final String value;
  final VoidCallback onTap;
  final IconData? icon;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 20, color: c.textSecondary), const SizedBox(width: 10)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: TextStyle(fontSize: 12, color: c.textSecondary)),
                      Text(value, style: const TextStyle(fontSize: 15, fontFeatures: tabular)),
                    ],
                  ),
                ),
                if (onClear != null)
                  IconButton(tooltip: 'Limpar $label', icon: const Icon(Icons.close, size: 18), onPressed: onClear),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- lembretes

class RemindersEditor extends StatelessWidget {
  const RemindersEditor({super.key, required this.reminders, required this.onChanged, required this.relativeTo});
  final List<Reminder> reminders;
  final ValueChanged<List<Reminder>> onChanged;

  /// "do prazo" ou "do início" (texto de ajuda).
  final String relativeTo;

  static const presets = [0, 5, 15, 30, 60, 120, 1440];

  Future<void> _add(BuildContext context) async {
    final choice = await showModalBottomSheet<Object>(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: SectionTitle('Lembrete ($relativeTo)')),
              for (final m in presets)
                ListTile(
                  leading: const Icon(Icons.notifications_none),
                  title: Text(Reminder.relative(m).label),
                  onTap: () => Navigator.pop(ctx, m),
                ),
              ListTile(
                leading: const Icon(Icons.event_outlined),
                title: const Text('Data e hora específicas…'),
                onTap: () => Navigator.pop(ctx, 'abs'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    if (choice is int) {
      onChanged([...reminders, Reminder.relative(choice)]);
      return;
    }
    final d = await pickDate(context, null, first: dateOnly(DateTime.now()));
    if (d == null || !context.mounted) return;
    final m = await pickTime(context, 9 * 60);
    if (m == null) return;
    onChanged([...reminders, Reminder.absolute(atMinutes(d, m))]);
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final (i, r) in reminders.indexed)
          InputChip(
            avatar: const Icon(Icons.notifications_active_outlined, size: 18),
            label: Text(r.label),
            onDeleted: () => onChanged([...reminders]..removeAt(i)),
            deleteButtonTooltipMessage: 'Remover lembrete',
          ),
        ActionChip(
          avatar: const Icon(Icons.add, size: 18),
          label: const Text('Lembrete'),
          onPressed: () => _add(context),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- categoria

class CategoryPicker extends ConsumerWidget {
  const CategoryPicker({super.key, required this.value, required this.onChanged});
  final int? value;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final visible = cats.where((c) => c.active || c.id == value).toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ChoiceChip(label: const Text('Nenhuma'), selected: value == null, onSelected: (_) => onChanged(null)),
        for (final c in visible)
          ChoiceChip(
            avatar: Icon(
              categoryIcon(c.icon),
              size: 18,
              color: value == c.id ? context.colors.onAccent : hexColor(c.color),
            ),
            label: Text(c.name),
            selected: value == c.id,
            onSelected: (_) => onChanged(c.id),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------- tags

class TagsField extends ConsumerStatefulWidget {
  const TagsField({super.key, required this.tags, required this.onChanged});
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<TagsField> createState() => _TagsFieldState();
}

class _TagsFieldState extends ConsumerState<TagsField> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final names = raw.split(RegExp(r'[\s,]+')).map(normalizeTagName).where((s) => s.isNotEmpty);
    final next = [...widget.tags];
    for (final n in names) {
      if (!next.contains(n)) next.add(n);
    }
    _text.clear();
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(tagsProvider).value ?? const <Tag>[];
    final q = normalizeText(normalizeTagName(_text.text));
    final suggestions = all
        .where((t) => !widget.tags.contains(t.name) && (q.isEmpty || normalizeText(t.name).contains(q)))
        .take(8)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in widget.tags)
                InputChip(
                  label: Text('#$t'),
                  onDeleted: () => widget.onChanged([...widget.tags]..remove(t)),
                  deleteButtonTooltipMessage: 'Remover tag',
                ),
            ],
          ),
        const SizedBox(height: 8),
        TextField(
          controller: _text,
          decoration: InputDecoration(
            hintText: 'Adicionar tag (ex.: casa)',
            prefixText: '#',
            suffixIcon: IconButton(
              tooltip: 'Adicionar tag',
              icon: const Icon(Icons.add),
              onPressed: () => _add(_text.text),
            ),
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: _add,
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final t in suggestions) ActionChip(label: Text('#${t.name}'), onPressed: () => _add(t.name)),
            ],
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- recorrência

class RecurrenceField extends StatelessWidget {
  const RecurrenceField({
    super.key,
    required this.rule,
    required this.start,
    required this.onChanged,
    this.enabled = true,
  });
  final RecurrenceRule? rule;
  final DateTime? start;
  final ValueChanged<RecurrenceRule?> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final s = start ?? dateOnly(DateTime.now());
    return FieldButton(
      label: 'Repetir',
      icon: Icons.repeat,
      value: rule == null ? 'Não repete' : describeRecurrence(rule!, s),
      onTap: () async {
        if (!enabled) {
          showSnack(context, 'Escolha uma data primeiro.');
          return;
        }
        final r = await showModalBottomSheet<_RuleResult>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => RecurrenceEditor(initial: rule, start: s),
        );
        if (r != null) onChanged(r.rule);
      },
      onClear: rule == null ? null : () => onChanged(null),
    );
  }
}

class _RuleResult {
  const _RuleResult(this.rule);
  final RecurrenceRule? rule;
}

enum _End { nunca, ate, vezes }

/// Editor amigável: "A cada 2 semanas, seg e qua, até 30/06".
class RecurrenceEditor extends StatefulWidget {
  const RecurrenceEditor({super.key, required this.initial, required this.start});
  final RecurrenceRule? initial;
  final DateTime start;

  @override
  State<RecurrenceEditor> createState() => _RecurrenceEditorState();
}

class _RecurrenceEditorState extends State<RecurrenceEditor> {
  late Freq _freq = widget.initial?.freq ?? Freq.semanal;
  late int _interval = widget.initial?.interval ?? 1;
  late Set<int> _days = {...?widget.initial?.weekdays};
  late MonthlyMode _monthly = widget.initial?.monthlyMode ?? MonthlyMode.diaDoMes;
  late _End _end = widget.initial?.until != null
      ? _End.ate
      : widget.initial?.count != null
      ? _End.vezes
      : _End.nunca;
  late DateTime _until = widget.initial?.until ?? addDays(widget.start, 30);
  late int _count = widget.initial?.count ?? 10;

  RecurrenceRule get _rule => RecurrenceRule(
    id: widget.initial?.id,
    freq: _freq,
    interval: _interval,
    weekdays: _freq == Freq.semanal ? (_days.isEmpty ? [widget.start.weekday] : (_days.toList()..sort())) : const [],
    monthlyMode: _freq == Freq.mensal ? _monthly : null,
    until: _end == _End.ate ? _until : null,
    count: _end == _End.vezes ? _count : null,
  );

  String _unit(int n) => switch (_freq) {
    Freq.diaria => n == 1 ? 'dia' : 'dias',
    Freq.semanal => n == 1 ? 'semana' : 'semanas',
    Freq.mensal => n == 1 ? 'mês' : 'meses',
    Freq.anual => n == 1 ? 'ano' : 'anos',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final s = widget.start;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('REPETIR', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              describeRecurrence(_rule, s),
              style: TextStyle(color: c.accent, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in Freq.values)
                  ChoiceChip(label: Text(f.label), selected: _freq == f, onSelected: (_) => setState(() => _freq = f)),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('A cada'),
                IconButton(
                  tooltip: 'Diminuir intervalo',
                  onPressed: _interval > 1 ? () => setState(() => _interval--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('$_interval', style: numberStyle(context, 22)),
                IconButton(
                  tooltip: 'Aumentar intervalo',
                  onPressed: _interval < 99 ? () => setState(() => _interval++) : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
                Text(_unit(_interval)),
              ],
            ),
            if (_freq == Freq.semanal) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var d = 1; d <= 7; d++)
                    FilterChip(
                      label: Text(weekdayShort[d]),
                      selected: _days.contains(d) || (_days.isEmpty && d == s.weekday),
                      onSelected: (v) => setState(() {
                        if (_days.isEmpty) _days = {s.weekday};
                        v ? _days.add(d) : _days.remove(d);
                      }),
                    ),
                ],
              ),
            ],
            if (_freq == Freq.mensal) ...[
              const SizedBox(height: 8),
              SegmentedButton<MonthlyMode>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(value: MonthlyMode.diaDoMes, label: Text('Todo dia ${s.day}')),
                  ButtonSegment(
                    value: MonthlyMode.diaDaSemana,
                    label: Text('${weekOfMonth(s)}ª ${weekdayShort[s.weekday]}'),
                  ),
                ],
                selected: {_monthly},
                onSelectionChanged: (v) => setState(() => _monthly = v.first),
              ),
              if (_monthly == MonthlyMode.diaDoMes && s.day > 28)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Meses sem dia ${s.day} são pulados.',
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ),
            ],
            if (_freq == Freq.anual && s.month == 2 && s.day == 29)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('Anos sem 29/02 são pulados.', style: TextStyle(fontSize: 12, color: c.textSecondary)),
              ),
            const SectionTitle('Termina'),
            SegmentedButton<_End>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _End.nunca, label: Text('Nunca')),
                ButtonSegment(value: _End.ate, label: Text('Em data')),
                ButtonSegment(value: _End.vezes, label: Text('Após N')),
              ],
              selected: {_end},
              onSelectionChanged: (v) => setState(() => _end = v.first),
            ),
            const SizedBox(height: 8),
            if (_end == _End.ate)
              FieldButton(
                label: 'Até',
                icon: Icons.event,
                value: dayMonthYear(_until),
                onTap: () async {
                  final d = await pickDate(context, _until, first: s);
                  if (d != null) setState(() => _until = d);
                },
              ),
            if (_end == _End.vezes)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Menos vezes',
                    onPressed: _count > 1 ? () => setState(() => _count--) : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$_count', style: numberStyle(context, 22)),
                  IconButton(
                    tooltip: 'Mais vezes',
                    onPressed: () => setState(() => _count++),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                  Text(_count == 1 ? 'vez' : 'vezes'),
                ],
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const _RuleResult(null)),
                    child: const Text('Não repetir'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _RuleResult(_rule)),
                    child: const Text('Aplicar'),
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
