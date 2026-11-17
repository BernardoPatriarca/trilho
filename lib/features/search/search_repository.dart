// Busca sobre a coluna `busca` (minúsculo, sem acento) + filtros do domínio,
// e filtros salvos.
import 'package:sqflite/sqflite.dart';

import '../../domain/dates.dart';
import '../../domain/event_expansion.dart';
import '../../domain/models.dart';
import '../../domain/search.dart';
import '../../domain/text.dart';

class SavedFilter {
  const SavedFilter({this.id, required this.name, required this.criteria});
  final int? id;
  final String name;
  final SearchCriteria criteria;
}

class SearchResults {
  const SearchResults({this.tasks = const [], this.events = const []});
  final List<Task> tasks;

  /// Eventos (a série aparece uma vez) com a próxima ocorrência relevante.
  final List<EventOccurrence> events;

  bool get isEmpty => tasks.isEmpty && events.isEmpty;
}

class SearchRepository {
  SearchRepository(this.db);
  final Database db;

  Future<SearchResults> search(SearchCriteria c, DateTime now, {bool mondayFirst = true}) async {
    final terms = searchTerms(c.text);
    // O texto filtra no SQL (LIKE na coluna busca); o resto, no domínio.
    final where = terms.map((_) => 'busca LIKE ?').join(' AND ');
    final args = terms.map((t) => '%$t%').toList();

    final tasks = <Task>[];
    if (c.includeTasks) {
      final rows = await db.query('tarefa', where: where.isEmpty ? null : where, whereArgs: args);
      final ids = rows.map((r) => r['id'] as int).toList();
      final tagIds = <int, Set<int>>{};
      final counts = <int, int>{};
      if (ids.isNotEmpty) {
        final inList = ids.join(',');
        for (final r in await db.rawQuery('SELECT tarefa_id, tag_id FROM tarefa_tag WHERE tarefa_id IN ($inList)')) {
          tagIds.putIfAbsent(r['tarefa_id'] as int, () => {}).add(r['tag_id'] as int);
        }
        for (final r in await db.rawQuery('SELECT tarefa_id, COUNT(*) AS n FROM checklist_item WHERE tarefa_id IN ($inList) GROUP BY tarefa_id')) {
          counts[r['tarefa_id'] as int] = r['n'] as int;
        }
      }
      for (final r in rows) {
        final t = Task.fromRow(r);
        final row = TaskSearchRow(task: t, index: r['busca'] as String, tagIds: tagIds[t.id] ?? const {}, checklistCount: counts[t.id] ?? 0);
        if (taskMatches(row, c, now, mondayFirst: mondayFirst)) tasks.add(t);
      }
      tasks.sort((a, b) {
        // Pendentes primeiro, depois por prazo.
        if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
        final da = a.dueDateTime, dbb = b.dueDateTime;
        if (da == null || dbb == null) return da == null ? (dbb == null ? 0 : 1) : -1;
        return da.compareTo(dbb);
      });
    }

    final events = <EventOccurrence>[];
    if (c.includeEvents && !c.hasTaskOnlyFilters) {
      final rows = await db.query('evento', where: where.isEmpty ? null : where, whereArgs: args);
      final tagIds = <int, Set<int>>{};
      for (final r in await db.query('evento_tag')) {
        tagIds.putIfAbsent(r['evento_id'] as int, () => {}).add(r['tag_id'] as int);
      }
      final events0 = rows.map(Event.fromRow).toList();
      final recIds = events0.map((e) => e.recurrenceId).whereType<int>().toList();
      final rules = <int, RecurrenceRule>{};
      final exceptions = <int, List<EventException>>{};
      if (recIds.isNotEmpty) {
        for (final r in await db.query('recorrencia', where: 'id IN (${recIds.join(',')})')) {
          rules[r['id'] as int] = RecurrenceRule.fromRow(r);
        }
        for (final r in await db.query('evento_excecao')) {
          final x = EventException.fromRow(r);
          exceptions.putIfAbsent(x.eventId, () => []).add(x);
        }
      }
      final range = c.range(now, mondayFirst: mondayFirst);
      final today = dateOnly(now);
      for (final (i, e) in events0.indexed) {
        final series = EventSeries(e, rule: rules[e.recurrenceId], exceptions: exceptions[e.id] ?? const []);
        List<EventOccurrence> occ;
        if (range != null) {
          occ = expandEvents([series], range.$1, range.$2);
        } else if (series.rule == null) {
          occ = expandEvents([series], e.start, e.end);
        } else {
          // Próxima ocorrência a partir de hoje (ou a última, se a série acabou).
          occ = expandEvents([series], today, addDays(today, 400));
          if (occ.isEmpty) occ = expandEvents([series], e.start, addDays(today, 1));
          if (occ.length > 1) occ = [occ.first];
        }
        final row = EventSearchRow(
          event: e,
          index: rows[i]['busca'] as String,
          tagIds: tagIds[e.id] ?? const {},
          occurrenceDates: occ.map((o) => o.occurrenceDate).toList(),
        );
        if (eventMatches(row, c, now, mondayFirst: mondayFirst) && occ.isNotEmpty) events.add(occ.first);
      }
      events.sort((a, b) => a.start.compareTo(b.start));
    }
    return SearchResults(tasks: tasks, events: events);
  }

  Future<List<SavedFilter>> savedFilters() async => (await db.query('filtro_salvo', orderBy: 'nome'))
      .map((r) => SavedFilter(id: r['id'] as int, name: r['nome'] as String, criteria: SearchCriteria.decode(r['json'] as String)))
      .toList();

  Future<int> saveFilter(String name, SearchCriteria c) async {
    final n = name.trim();
    if (n.isEmpty) throw ArgumentError('Dê um nome ao filtro.');
    return db.insert('filtro_salvo', {'nome': n, 'json': c.encode()}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteFilter(int id) => db.delete('filtro_salvo', where: 'id = ?', whereArgs: [id]);
}
