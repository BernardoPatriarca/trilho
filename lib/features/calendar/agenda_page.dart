// Aba Agenda: visões Mês, Semana, Dia e Lista. Botão "Hoje", deslizar para
// mudar de período e "Mostrar tarefas no calendário".
// O table_calendar ainda usa o Material antigo (flutter/material.dart), que no
// Flutter 3.50 é uma árvore separada do material_ui: o calendário precisa de
// um Material dessa biblioteca acima dele para os toques (InkWell) do cabeçalho.
// ignore: deprecated_member_use
import 'package:flutter/material.dart' as legacy;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:table_calendar/table_calendar.dart' hide isSameDay;

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../core/utils/icons.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/event_tile.dart';
import '../../core/widgets/task_tile.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../settings/config_repository.dart';
import '../tasks/tasks_page.dart';
import 'time_grid.dart';

enum AgendaView {
  mes('Mês'),
  semana('Semana'),
  dia('Dia'),
  lista('Lista');

  const AgendaView(this.label);
  final String label;
}

class AgendaPage extends ConsumerStatefulWidget {
  const AgendaPage({super.key});

  @override
  ConsumerState<AgendaPage> createState() => _AgendaPageState();
}

class _AgendaPageState extends ConsumerState<AgendaPage> {
  AgendaView _view = AgendaView.mes;
  late DateTime _focused;
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _focused = dateOnly(ref.read(clockProvider)());
    _selected = _focused;
  }

  void _goToday() {
    final t = dateOnly(ref.read(clockProvider)());
    setState(() {
      _focused = t;
      _selected = t;
    });
  }

  void _shift(int dir) {
    setState(() {
      switch (_view) {
        case AgendaView.mes:
          _focused = DateTime(_focused.year, _focused.month + dir, 1);
        case AgendaView.semana:
          _focused = addDays(_focused, 7 * dir);
        case AgendaView.dia:
          _focused = addDays(_focused, dir);
        case AgendaView.lista:
          _focused = addDays(_focused, 60 * dir);
      }
      _selected = _focused;
    });
  }

  Future<void> _toggleTasks(bool show) async {
    await ref.read(configRepositoryProvider).set(ConfigRepository.showTasksInCalendar, show ? '1' : '0');
    ref.dataChanged();
  }

  void _createAt(DateTime start) => context.push('/evento/novo', extra: start);

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider).value;
    final showTasks = cfg?.showTasksInCalendar ?? true;
    final mondayFirst = cfg?.mondayFirst ?? true;
    final now = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('AGENDA'),
        actions: [
          TextButton(onPressed: _goToday, child: const Text('Hoje')),
          IconButton(
            tooltip: showTasks ? 'Esconder tarefas do calendário' : 'Mostrar tarefas no calendário',
            isSelected: showTasks,
            icon: const Icon(Icons.checklist_outlined),
            selectedIcon: const Icon(Icons.checklist),
            onPressed: () => _toggleTasks(!showTasks),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: SearchLauncher()),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<AgendaView>(
                showSelectedIcon: false,
                segments: [for (final v in AgendaView.values) ButtonSegment(value: v, label: Text(v.label))],
                selected: {_view},
                onSelectionChanged: (s) => setState(() {
                  _view = s.first;
                  _focused = _selected;
                }),
              ),
            ),
          ),
          Expanded(
            child: switch (_view) {
              AgendaView.mes => _month(context, now, showTasks, mondayFirst),
              AgendaView.semana => _grid(context, now, showTasks, mondayFirst, week: true),
              AgendaView.dia => _grid(context, now, showTasks, mondayFirst, week: false),
              AgendaView.lista => _list(context, now, showTasks),
            },
          ),
        ],
      ),
    );
  }

  List<Task> _tasksIn(List<Task> all, DateTime from, DateTime to) => all
      .where(
        (t) =>
            t.dueDate != null &&
            !t.dueDate!.isBefore(from) &&
            !t.dueDate!.isAfter(to) &&
            t.status != TaskStatus.cancelada,
      )
      .toList();

  // ----------------------------------------------------------------- mês

  Widget _month(BuildContext context, DateTime now, bool showTasks, bool mondayFirst) {
    final c = context.colors;
    final gridStart = startOfWeek(startOfMonth(_focused), mondayFirst: mondayFirst);
    final gridEnd = addDays(gridStart, 41);
    final events = ref.watch(occurrencesProvider((gridStart, gridEnd)));
    final tasks = showTasks ? (ref.watch(taskListProvider).value?.tasks ?? const <Task>[]) : const <Task>[];
    final cats = ref.watch(categoryMapProvider);
    final occ = events.value ?? const <EventOccurrence>[];
    final monthTasks = _tasksIn(tasks, gridStart, gridEnd);

    List<Object> itemsOn(DateTime d) => [
      ...occ.where((e) => e.occursOn(d)),
      ...monthTasks.where((t) => isSameDay(t.dueDate!, d)),
    ];

    final dayItems = itemsOn(_selected);
    final dayEvents = dayItems.whereType<EventOccurrence>().toList();
    final dayTasks = dayItems.whereType<Task>().toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 96),
      children: [
        legacy.Material(
          type: legacy.MaterialType.transparency,
          child: TableCalendar<Object>(
            locale: 'pt_BR',
            firstDay: DateTime(2000),
            lastDay: DateTime(2100, 12, 31),
            focusedDay: _focused,
            currentDay: now,
            selectedDayPredicate: (d) => isSameDay(d, _selected),
            startingDayOfWeek: mondayFirst ? StartingDayOfWeek.monday : StartingDayOfWeek.sunday,
            availableCalendarFormats: const {CalendarFormat.month: 'Mês'},
            availableGestures: AvailableGestures.horizontalSwipe,
            eventLoader: itemsOn,
            rowHeight: 52,
            daysOfWeekHeight: 24,
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextFormatter: (d, locale) {
                final s = longMonthYear(d);
                return s[0].toUpperCase() + s.substring(1);
              },
              titleTextStyle: Theme.of(context).textTheme.titleLarge!,
              leftChevronIcon: Icon(Icons.chevron_left, color: c.text, semanticLabel: 'Mês anterior'),
              rightChevronIcon: Icon(Icons.chevron_right, color: c.text, semanticLabel: 'Próximo mês'),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: TextStyle(fontSize: 12, color: c.textSecondary),
              weekendStyle: TextStyle(fontSize: 12, color: c.textSecondary),
              dowTextFormatter: (d, _) => weekdayShort[d.weekday],
            ),
            calendarStyle: CalendarStyle(
              outsideDaysVisible: true,
              defaultTextStyle: TextStyle(color: c.text, fontFeatures: tabular),
              weekendTextStyle: TextStyle(color: c.text, fontFeatures: tabular),
              outsideTextStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.5), fontFeatures: tabular),
              todayDecoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.accent, width: 2),
              ),
              todayTextStyle: TextStyle(color: c.text, fontWeight: FontWeight.w700, fontFeatures: tabular),
              selectedDecoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
              selectedTextStyle: TextStyle(color: c.onAccent, fontWeight: FontWeight.w700, fontFeatures: tabular),
              markersMaxCount: 4,
            ),
            calendarBuilders: CalendarBuilders<Object>(
              markerBuilder: (context, day, items) {
                if (items.isEmpty) return null;
                final colors = <Color>[
                  for (final i in items.take(4))
                    i is EventOccurrence ? hexColor(cats[i.categoryId]?.color, c.accent) : c.textSecondary,
                ];
                return Positioned(
                  bottom: 4,
                  child: Semantics(
                    label: '${items.length} ite${items.length == 1 ? 'm' : 'ns'}',
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (k, col) in colors.indexed)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: items[k] is Task ? Colors.transparent : col,
                              border: items[k] is Task ? Border.all(color: col, width: 1.5) : null,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
            onDaySelected: (sel, foc) => setState(() {
              _selected = dateOnly(sel);
              _focused = dateOnly(foc);
            }),
            onPageChanged: (foc) => setState(() => _focused = dateOnly(foc)),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SectionTitle(_capitalize(longDate(_selected).toLowerCase())),
        ),
        if (dayEvents.isEmpty && dayTasks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: AppCard(
              onTap: () => _createAt(atMinutes(_selected, 9 * 60)),
              child: Row(
                children: [
                  Icon(Icons.event_available_outlined, color: c.textSecondary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nada neste dia. Toque para criar um evento.',
                      style: TextStyle(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        for (final e in dayEvents) Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: EventTile(e)),
        for (final t in dayTasks)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: TaskTile(
              task: t,
              progress: ref.watch(taskListProvider).value?.progressOf(t) ?? ChecklistProgress.empty,
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------- semana/dia

  Widget _grid(BuildContext context, DateTime now, bool showTasks, bool mondayFirst, {required bool week}) {
    final c = context.colors;
    final first = week ? startOfWeek(_focused, mondayFirst: mondayFirst) : _focused;
    final days = [for (var i = 0; i < (week ? 7 : 1); i++) addDays(first, i)];
    final events = ref.watch(occurrencesProvider((days.first, days.last)));
    final tasks = showTasks
        ? _tasksIn(ref.watch(taskListProvider).value?.tasks ?? const [], days.first, days.last)
        : const <Task>[];
    final title = week
        ? '${dayMonth(days.first)} – ${dayMonth(days.last)}'
        : _capitalize(longDate(_focused).toLowerCase());

    return GestureDetector(
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v.abs() < 250) return;
        _shift(v < 0 ? 1 : -1);
      },
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: week ? 'Semana anterior' : 'Dia anterior',
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _shift(-1),
              ),
              Expanded(
                child: Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(
                tooltip: week ? 'Próxima semana' : 'Próximo dia',
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _shift(1),
              ),
            ],
          ),
          if (!week)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Toque e segure num horário vazio para criar um evento.',
                style: TextStyle(fontSize: 12, color: c.textSecondary),
              ),
            ),
          Expanded(
            child: AsyncView(
              events,
              builder: (occ) => TimeGrid(
                key: ValueKey('${days.first}-${days.length}'),
                days: days,
                events: occ,
                tasks: tasks,
                now: now,
                onCreateAt: _createAt,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- lista

  Widget _list(BuildContext context, DateTime now, bool showTasks) {
    final from = _focused;
    final to = addDays(from, 59);
    final events = ref.watch(occurrencesProvider((from, to)));
    final data = ref.watch(taskListProvider).value;
    final tasks = showTasks
        ? _tasksIn(data?.tasks ?? const [], from, to).where((t) => t.isPending).toList()
        : const <Task>[];
    return AsyncView(
      events,
      builder: (occ) {
        final days = <DateTime>[];
        for (var i = 0; i < 60; i++) {
          final d = addDays(from, i);
          if (occ.any((e) => e.occursOn(d)) || tasks.any((t) => isSameDay(t.dueDate!, d))) days.add(d);
        }
        if (days.isEmpty) {
          return ListView(
            children: const [
              EmptyState(
                icon: Icons.event_note_outlined,
                title: 'Nada nos próximos 60 dias',
                message: 'Toque em + para criar um evento.',
              ),
            ],
          );
        }
        return GestureDetector(
          onHorizontalDragEnd: (d) {
            final v = d.primaryVelocity ?? 0;
            if (v.abs() > 400) _shift(v < 0 ? 1 : -1);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              Text(
                '${dayMonthYear(from)} a ${dayMonthYear(to)}',
                style: TextStyle(color: context.colors.textSecondary, fontSize: 12),
              ),
              for (final d in days) ...[
                SectionTitle(_capitalize(relativeDay(d, now) == 'hoje' ? 'Hoje · ${longDate(d)}' : longDate(d))),
                for (final e in occ.where((e) => e.occursOn(d)))
                  Padding(padding: const EdgeInsets.only(bottom: 8), child: EventTile(e)),
                for (final t in tasks.where((t) => isSameDay(t.dueDate!, d)))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TaskTile(task: t, progress: data?.progressOf(t) ?? ChecklistProgress.empty, showDue: false),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

String _capitalize(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
