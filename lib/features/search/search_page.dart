// Busca: campo no topo, resultados agrupados (Tarefas, Eventos) com o termo
// destacado, filtros combináveis num bottom sheet e filtros salvos.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/utils/icons.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/event_tile.dart';
import '../../core/widgets/task_tile.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/priority.dart';
import '../../domain/search.dart';
import 'search_repository.dart';

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.initial});
  final SearchCriteria? initial;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  late SearchCriteria _c = widget.initial ?? SearchCriteria.empty;
  late final _text = TextEditingController(text: _c.text);
  Timer? _debounce;
  SearchResults? _results;
  bool _loading = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (!_c.isEmpty) _run();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final seq = ++_seq;
    if (_c.isEmpty) {
      setState(() => _results = null);
      return;
    }
    setState(() => _loading = true);
    final cfg = await ref.read(configProvider.future);
    final r = await ref.read(searchRepositoryProvider).search(_c, ref.now(), mondayFirst: cfg.mondayFirst);
    if (!mounted || seq != _seq) return;
    setState(() {
      _results = r;
      _loading = false;
    });
  }

  void _onText(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () {
      _c = _c.copyWith(text: v);
      _run();
    });
  }

  Future<void> _openFilters() async {
    final r = await showModalBottomSheet<SearchCriteria>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FiltersSheet(initial: _c),
    );
    if (r != null) {
      setState(() => _c = r.copyWith(text: _text.text));
      _run();
    }
  }

  Future<void> _saveFilter() async {
    final name = await askText(context, title: 'Salvar filtro', hint: 'Ex.: Urgentes do trabalho');
    if (name == null || name.trim().isEmpty) return;
    try {
      await ref.read(searchRepositoryProvider).saveFilter(name, _c.copyWith(text: _text.text));
      ref.dataChanged();
      if (mounted) showSnack(context, 'Filtro "${name.trim()}" salvo');
    } on ArgumentError catch (e) {
      if (mounted) showSnack(context, '${e.message}');
    }
  }

  void _apply(SavedFilter f) {
    setState(() {
      _c = f.criteria;
      _text.text = f.criteria.text;
    });
    _run();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final saved = ref.watch(savedFiltersProvider).value ?? const <SavedFilter>[];
    ref.listen(dataRevisionProvider, (_, _) => _run());
    final n = _c.activeFilters;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: TextField(
          key: const Key('searchField'),
          controller: _text,
          autofocus: widget.initial == null,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Buscar tarefas, eventos, itens…',
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            suffixIcon: _text.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _text.clear();
                      _onText('');
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (v) {
            setState(() {});
            _onText(v);
          },
        ),
        actions: [
          IconButton(
            tooltip: n == 0 ? 'Filtros' : 'Filtros ($n ativos)',
            icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.tune)),
            onPressed: _openFilters,
          ),
          if (!_c.isEmpty)
            IconButton(tooltip: 'Salvar filtro', icon: const Icon(Icons.bookmark_add_outlined), onPressed: _saveFilter),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          if (saved.isNotEmpty) ...[
            const SectionTitle('Filtros salvos'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final f in saved)
                  InputChip(
                    avatar: const Icon(Icons.bookmark_outline, size: 18),
                    label: Text(f.name),
                    onPressed: () => _apply(f),
                    onDeleted: () async {
                      final ok = await confirm(
                        context,
                        title: 'Excluir filtro "${f.name}"?',
                        confirmLabel: 'Excluir',
                        destructive: true,
                      );
                      if (!ok) return;
                      await ref.read(searchRepositoryProvider).deleteFilter(f.id!);
                      ref.dataChanged();
                    },
                    deleteButtonTooltipMessage: 'Excluir filtro',
                  ),
              ],
            ),
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (!_loading && _results == null)
            const EmptyState(
              icon: Icons.search,
              title: 'O que você procura?',
              message: 'Busque no título, na descrição e nos itens da checklist. Ex.: "óleo" acha a tarefa do mercado.',
            ),
          if (!_loading && _results != null && _results!.isEmpty)
            EmptyState(
              icon: Icons.search_off,
              title: 'Nada encontrado',
              message: n > 0 ? 'Tente tirar algum filtro.' : 'Tente outra palavra.',
            ),
          if (!_loading && _results != null && _results!.tasks.isNotEmpty) ...[
            SectionTitle('Tarefas (${_results!.tasks.length})'),
            for (final t in _results!.tasks)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: TaskTile(
                  task: t,
                  highlight: _c.text,
                  progress: ref.watch(taskListProvider).value?.progressOf(t) ?? ChecklistProgress.empty,
                ),
              ),
          ],
          if (!_loading && _results != null && _results!.events.isNotEmpty) ...[
            SectionTitle('Eventos (${_results!.events.length})'),
            for (final e in _results!.events)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: EventTile(e, showDate: true, highlight: _c.text),
              ),
          ],
          if (_results != null && _c.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'A busca ignora acentos e maiúsculas.',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}

class FiltersSheet extends ConsumerStatefulWidget {
  const FiltersSheet({super.key, required this.initial});
  final SearchCriteria initial;

  @override
  ConsumerState<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<FiltersSheet> {
  late SearchCriteria _c = widget.initial;

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('FILTROS', style: Theme.of(context).textTheme.titleLarge),
            const SectionTitle('Tipo'),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Tarefas'),
                  selected: _c.includeTasks,
                  onSelected: (v) => setState(() => _c = _c.copyWith(includeTasks: v || !_c.includeEvents)),
                ),
                FilterChip(
                  label: const Text('Eventos'),
                  selected: _c.includeEvents,
                  onSelected: (v) => setState(() => _c = _c.copyWith(includeEvents: v || !_c.includeTasks)),
                ),
              ],
            ),
            const SectionTitle('Período'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (p, label) in const [
                  (SearchPeriod.qualquer, 'Qualquer'),
                  (SearchPeriod.hoje, 'Hoje'),
                  (SearchPeriod.semana, 'Esta semana'),
                  (SearchPeriod.mes, 'Este mês'),
                  (SearchPeriod.personalizado, 'Intervalo…'),
                ])
                  ChoiceChip(
                    label: Text(
                      p == SearchPeriod.personalizado && _c.period == p && _c.from != null
                          ? '${dayMonth(_c.from!)} – ${dayMonth(_c.to!)}'
                          : label,
                    ),
                    selected: _c.period == p,
                    onSelected: (_) async {
                      if (p != SearchPeriod.personalizado) {
                        setState(() => _c = _c.copyWith(period: p));
                        return;
                      }
                      final now = ref.read(clockProvider)();
                      final r = await showDateRangePicker(
                        context: context,
                        firstDate: DateTime(now.year - 5),
                        lastDate: DateTime(now.year + 5),
                        initialDateRange: DateTimeRange(start: dateOnly(now), end: addDays(dateOnly(now), 7)),
                      );
                      if (r != null) setState(() => _c = _c.copyWith(period: p, from: r.start, to: r.end));
                    },
                  ),
              ],
            ),
            if (cats.isNotEmpty) ...[
              const SectionTitle('Categorias'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final cat in cats)
                    FilterChip(
                      avatar: Icon(
                        categoryIcon(cat.icon),
                        size: 16,
                        color: _c.categoryIds.contains(cat.id) ? context.colors.onAccent : hexColor(cat.color),
                      ),
                      label: Text(cat.name),
                      selected: _c.categoryIds.contains(cat.id),
                      onSelected: (_) =>
                          setState(() => _c = _c.copyWith(categoryIds: _toggle(_c.categoryIds, cat.id!))),
                    ),
                ],
              ),
            ],
            if (tags.isNotEmpty) ...[
              const SectionTitle('Tags'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in tags)
                    FilterChip(
                      label: Text('#${t.name}'),
                      selected: _c.tagIds.contains(t.id),
                      onSelected: (_) => setState(() => _c = _c.copyWith(tagIds: _toggle(_c.tagIds, t.id!))),
                    ),
                ],
              ),
            ],
            const SectionTitle('Prioridade (só tarefas)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in Priority.values)
                  FilterChip(
                    avatar: CircleAvatar(radius: 6, backgroundColor: priorityColor(p)),
                    label: Text('${p.code} ${p.label}'),
                    selected: _c.priorities.contains(p.value),
                    onSelected: (_) => setState(() => _c = _c.copyWith(priorities: _toggle(_c.priorities, p.value))),
                  ),
              ],
            ),
            const SectionTitle('Status (só tarefas)'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in TaskStatus.values)
                  FilterChip(
                    label: Text(s.label),
                    selected: _c.statuses.contains(s),
                    onSelected: (_) => setState(() => _c = _c.copyWith(statuses: _toggle(_c.statuses, s))),
                  ),
              ],
            ),
            const SectionTitle('Outros'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('Com prazo'),
                  selected: _c.withDue == true,
                  onSelected: (v) =>
                      setState(() => _c = v ? _c.copyWith(withDue: true) : _c.copyWith(clearWithDue: true)),
                ),
                ChoiceChip(
                  label: const Text('Sem prazo'),
                  selected: _c.withDue == false,
                  onSelected: (v) =>
                      setState(() => _c = v ? _c.copyWith(withDue: false) : _c.copyWith(clearWithDue: true)),
                ),
                FilterChip(
                  label: const Text('Só atrasadas'),
                  selected: _c.onlyOverdue,
                  onSelected: (v) => setState(() => _c = _c.copyWith(onlyOverdue: v)),
                ),
                FilterChip(
                  label: const Text('Com checklist'),
                  selected: _c.withChecklist,
                  onSelected: (v) => setState(() => _c = _c.copyWith(withChecklist: v)),
                ),
                FilterChip(
                  label: const Text('Recorrentes'),
                  selected: _c.onlyRecurring,
                  onSelected: (v) => setState(() => _c = _c.copyWith(onlyRecurring: v)),
                ),
              ],
            ),
            if (_c.hasTaskOnlyFilters && _c.includeEvents)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Com filtros de tarefa ligados, eventos não aparecem.',
                  style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => _c = SearchCriteria(text: _c.text)),
                    child: const Text('Limpar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(onPressed: () => Navigator.pop(context, _c), child: const Text('Aplicar')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
