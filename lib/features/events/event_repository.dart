// Eventos: CRUD, recorrência com exceções e edição "só este / este e os
// seguintes / todos".
import 'package:sqflite/sqflite.dart';

import '../../domain/dates.dart';
import '../../domain/event_expansion.dart';
import '../../domain/models.dart';
import '../../domain/recurrence.dart';
import '../../domain/tasks.dart';
import '../../domain/text.dart';
import '../categories/category_repository.dart';
import '../tasks/task_repository.dart';

enum EditScope {
  onlyThis('Só este evento'),
  thisAndFollowing('Este e os seguintes'),
  all('Todos');

  const EditScope(this.label);
  final String label;
}

class EventDetails {
  const EventDetails({required this.event, this.rule, this.tags = const [], this.reminders = const [], this.exceptions = const []});
  final Event event;
  final RecurrenceRule? rule;
  final List<Tag> tags;
  final List<Reminder> reminders;
  final List<EventException> exceptions;
}

class EventDraft {
  const EventDraft({
    required this.event,
    this.rule,
    this.tagNames = const [],
    this.reminders = const [],
    this.remindersTouched = false,
  });
  final Event event;
  final RecurrenceRule? rule;
  final List<String> tagNames;
  final List<Reminder> reminders;
  final bool remindersTouched;
}

class EventRepository {
  EventRepository(this.db) : tags = TagRepository(db);
  final Database db;
  final TagRepository tags;

  /// Séries que podem ter ocorrências em [from]..[to]: as recorrentes e as
  /// únicas que tocam o intervalo (usa o índice de `inicio`).
  Future<List<EventSeries>> seriesInRange(DateTime from, DateTime to) async {
    final rows = await db.query('evento',
        where: 'recorrencia_id IS NOT NULL OR (inicio < ? AND fim >= ?)',
        whereArgs: [toIsoDate(addDays(dateOnly(to), 1)), toIsoDate(dateOnly(from))]);
    return _withRules(rows);
  }

  Future<List<EventSeries>> allSeries() async => _withRules(await db.query('evento', orderBy: 'inicio'));

  Future<List<EventSeries>> _withRules(List<Map<String, Object?>> rows) async {
    final events = rows.map(Event.fromRow).toList();
    final recIds = events.map((e) => e.recurrenceId).whereType<int>().toList();
    final rules = <int, RecurrenceRule>{};
    final exceptions = <int, List<EventException>>{};
    if (recIds.isNotEmpty) {
      for (final r in await db.query('recorrencia', where: 'id IN (${recIds.join(',')})')) {
        rules[r['id'] as int] = RecurrenceRule.fromRow(r);
      }
      final evIds = events.where((e) => e.recurrenceId != null).map((e) => e.id).join(',');
      for (final r in await db.query('evento_excecao', where: 'evento_id IN ($evIds)')) {
        final x = EventException.fromRow(r);
        exceptions.putIfAbsent(x.eventId, () => []).add(x);
      }
    }
    return [
      for (final e in events)
        EventSeries(e, rule: e.recurrenceId == null ? null : rules[e.recurrenceId], exceptions: exceptions[e.id] ?? const []),
    ];
  }

  Future<Map<int, Set<int>>> tagIdsByEvent() async {
    final out = <int, Set<int>>{};
    for (final r in await db.query('evento_tag')) {
      out.putIfAbsent(r['evento_id'] as int, () => {}).add(r['tag_id'] as int);
    }
    return out;
  }

  Future<Map<int, String>> searchIndexes() async {
    final rows = await db.query('evento', columns: ['id', 'busca']);
    return {for (final r in rows) r['id'] as int: r['busca'] as String};
  }

  /// Lembretes de todos os eventos (para o agendador).
  Future<Map<int, List<Reminder>>> allReminders() async {
    final out = <int, List<Reminder>>{};
    for (final r in await db.query('lembrete', where: "alvo_tipo = 'evento'", orderBy: 'id')) {
      final rem = Reminder.fromRow(r);
      out.putIfAbsent(rem.targetId!, () => []).add(rem);
    }
    return out;
  }

  Future<EventDetails?> get(int id) async {
    final rows = await db.query('evento', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final e = Event.fromRow(rows.first);
    final rule = e.recurrenceId == null
        ? null
        : (await db.query('recorrencia', where: 'id = ?', whereArgs: [e.recurrenceId])).map(RecurrenceRule.fromRow).firstOrNull;
    return EventDetails(
      event: e,
      rule: rule,
      tags: (await db.rawQuery('SELECT t.* FROM tag t JOIN evento_tag et ON et.tag_id = t.id WHERE et.evento_id = ? ORDER BY t.nome', [id]))
          .map(Tag.fromRow)
          .toList(),
      reminders: (await db.query('lembrete', where: "alvo_tipo = 'evento' AND alvo_id = ?", whereArgs: [id], orderBy: 'id'))
          .map(Reminder.fromRow)
          .toList(),
      exceptions: (await db.query('evento_excecao', where: 'evento_id = ?', whereArgs: [id])).map(EventException.fromRow).toList(),
    );
  }

  void _validate(EventDraft d) {
    final e = d.event;
    final error = validateEvent(title: e.title, start: e.start, end: e.end, allDay: e.allDay) ?? validateRule(d.rule, e.start);
    if (error != null) throw ValidationException(error);
  }

  /// Salva a série inteira (evento novo, evento único ou "Todos").
  Future<int> save(EventDraft d, {required DateTime now, int defaultReminderMin = 15}) async {
    _validate(d);
    return db.transaction((txn) => _save(txn, d, now: now, defaultReminderMin: defaultReminderMin));
  }

  Future<int> _save(Transaction txn, EventDraft d, {required DateTime now, required int defaultReminderMin}) async {
    final e = d.event;
    final isNew = e.id == null;
    int? recId = e.recurrenceId;
    if (d.rule != null) {
      if (recId != null) {
        await txn.update('recorrencia', d.rule!.toRow(), where: 'id = ?', whereArgs: [recId]);
      } else {
        recId = await txn.insert('recorrencia', d.rule!.toRow());
      }
    }
    final ev = e.copyWith(
      title: e.title.trim(),
      recurrenceId: recId,
      clearRecurrence: d.rule == null,
      updatedAt: now,
      createdAt: isNew ? now : e.createdAt,
      start: e.allDay ? dateOnly(e.start) : e.start,
      end: e.allDay ? dateOnly(e.end) : e.end,
    );
    final row = ev.toRow()..['busca'] = searchIndex([ev.title, ev.description, ev.location]);
    late int id;
    if (isNew) {
      id = await txn.insert('evento', row);
    } else {
      id = e.id!;
      await txn.update('evento', row, where: 'id = ?', whereArgs: [id]);
    }
    if (d.rule == null && e.recurrenceId != null) {
      await txn.delete('evento_excecao', where: 'evento_id = ?', whereArgs: [id]);
      await _deleteRuleIfUnused(txn, e.recurrenceId!);
    }
    await txn.delete('evento_tag', where: 'evento_id = ?', whereArgs: [id]);
    for (final tagId in await tags.idsFor(d.tagNames, txn: txn)) {
      await txn.insert('evento_tag', {'evento_id': id, 'tag_id': tagId});
    }
    var reminders = d.reminders;
    if (isNew && !d.remindersTouched && reminders.isEmpty) {
      reminders = [Reminder.relative(defaultReminderMin)];
    }
    await TaskRepository.replaceReminders(txn, TargetType.evento, id, reminders);
    return id;
  }

  Future<void> _deleteRuleIfUnused(DatabaseExecutor ex, int ruleId) async {
    final used = await ex.rawQuery(
        'SELECT (SELECT COUNT(*) FROM tarefa WHERE recorrencia_id = ?) + (SELECT COUNT(*) FROM evento WHERE recorrencia_id = ?) AS n',
        [ruleId, ruleId]);
    if ((used.first['n'] as int) == 0) await ex.delete('recorrencia', where: 'id = ?', whereArgs: [ruleId]);
  }

  /// Edita uma ocorrência de evento recorrente conforme o [scope].
  /// [draft] traz os valores novos (início/fim já na data da ocorrência).
  /// Retorna o id do evento que contém a ocorrência editada.
  Future<int> saveOccurrence(EditScope scope, EventOccurrence occ, EventDraft draft,
      {required DateTime now, int defaultReminderMin = 15}) async {
    _validate(draft);
    final series = occ.event;
    return db.transaction((txn) async {
      final rule = (await txn.query('recorrencia', where: 'id = ?', whereArgs: [series.recurrenceId]))
          .map(RecurrenceRule.fromRow)
          .firstOrNull;
      final isFirst = isSameDay(occ.occurrenceDate, series.start);
      if (rule == null || scope == EditScope.all || (scope == EditScope.thisAndFollowing && isFirst)) {
        // Todos: aplica o deslocamento feito nesta ocorrência à série inteira.
        final shift = draft.event.start.difference(occ.start);
        final newStart = series.allDay ? addDays(series.start, shift.inDays) : series.start.add(shift);
        final duration = draft.event.allDay
            ? Duration(days: daysBetween(draft.event.start, draft.event.end))
            : draft.event.end.difference(draft.event.start);
        final newEnd = draft.event.allDay ? addDays(newStart, duration.inDays) : newStart.add(duration);
        final ev = draft.event.copyWith(id: series.id, recurrenceId: series.recurrenceId, start: newStart, end: newEnd, createdAt: series.createdAt);
        return _save(txn, EventDraft(event: ev, rule: draft.rule, tagNames: draft.tagNames, reminders: draft.reminders, remindersTouched: true),
            now: now, defaultReminderMin: defaultReminderMin);
      }
      if (scope == EditScope.onlyThis) {
        final ex = EventException(
          eventId: series.id!,
          occurrenceDate: occ.occurrenceDate,
          newStart: draft.event.start,
          newEnd: draft.event.end,
          newTitle: draft.event.title.trim() == series.title ? null : draft.event.title.trim(),
        );
        await txn.insert('evento_excecao', ex.toRow(allDay: series.allDay), conflictAlgorithm: ConflictAlgorithm.replace);
        await txn.update('evento', {'atualizado_em': toIsoDateTime(now)}, where: 'id = ?', whereArgs: [series.id]);
        return series.id!;
      }
      // Este e os seguintes: encerra a série original na véspera e cria uma nova.
      await _endSeriesBefore(txn, series, rule, occ.occurrenceDate);
      var newRule = draft.rule;
      if (newRule != null && rule.count != null && newRule.count == rule.count) {
        final before = occurrencesBefore(rule, series.start, occ.occurrenceDate);
        newRule = newRule.copyWith(count: (rule.count! - before).clamp(1, rule.count!));
      }
      final ev = draft.event.copyWith(clearRecurrence: true, createdAt: now);
      final newEvent = Event(
        title: ev.title,
        description: ev.description,
        location: ev.location,
        categoryId: ev.categoryId,
        start: ev.start,
        end: ev.end,
        allDay: ev.allDay,
        createdAt: now,
        updatedAt: now,
      );
      return _save(txn, EventDraft(event: newEvent, rule: newRule?.withoutId(), tagNames: draft.tagNames, reminders: draft.reminders, remindersTouched: true),
          now: now, defaultReminderMin: defaultReminderMin);
    });
  }

  /// `ate` = véspera de [date] (ou a contagem até ela) e remove as exceções
  /// dali para frente.
  Future<void> _endSeriesBefore(Transaction txn, Event series, RecurrenceRule rule, DateTime date) async {
    final RecurrenceRule ended = rule.count != null
        ? rule.copyWith(count: occurrencesBefore(rule, series.start, date))
        : rule.copyWith(until: addDays(dateOnly(date), -1));
    await txn.update('recorrencia', ended.toRow(), where: 'id = ?', whereArgs: [rule.id]);
    await txn.delete('evento_excecao', where: 'evento_id = ? AND data_ocorrencia >= ?', whereArgs: [series.id, toIsoDate(date)]);
  }

  /// Exclui uma ocorrência conforme o [scope].
  Future<void> deleteOccurrence(EditScope scope, EventOccurrence occ, {required DateTime now}) async {
    final series = occ.event;
    if (series.recurrenceId == null || scope == EditScope.all) return delete(series.id!);
    final isFirst = isSameDay(occ.occurrenceDate, series.start);
    if (scope == EditScope.thisAndFollowing && isFirst) return delete(series.id!);
    await db.transaction((txn) async {
      if (scope == EditScope.onlyThis) {
        await txn.insert(
            'evento_excecao', EventException(eventId: series.id!, occurrenceDate: occ.occurrenceDate, cancelled: true).toRow(allDay: series.allDay),
            conflictAlgorithm: ConflictAlgorithm.replace);
      } else {
        final rule = (await txn.query('recorrencia', where: 'id = ?', whereArgs: [series.recurrenceId])).map(RecurrenceRule.fromRow).first;
        await _endSeriesBefore(txn, series, rule, occ.occurrenceDate);
      }
      await txn.update('evento', {'atualizado_em': toIsoDateTime(now)}, where: 'id = ?', whereArgs: [series.id]);
    });
  }

  Future<void> delete(int id) => db.transaction((txn) async {
        final rows = await txn.query('evento', columns: ['recorrencia_id'], where: 'id = ?', whereArgs: [id]);
        await txn.delete('lembrete', where: "alvo_tipo = 'evento' AND alvo_id = ?", whereArgs: [id]);
        await txn.delete('evento', where: 'id = ?', whereArgs: [id]);
        final recId = rows.isEmpty ? null : rows.first['recorrencia_id'] as int?;
        if (recId != null) await _deleteRuleIfUnused(txn, recId);
      });

  /// Seed de carga (só em debug): [n] eventos espalhados em ±6 meses.
  Future<void> seedLoad(int n, DateTime now) => db.transaction((txn) async {
        final batch = txn.batch();
        final base = addDays(dateOnly(now), -180);
        for (var i = 0; i < n; i++) {
          final day = addDays(base, (i * 7) % 360);
          final start = atMinutes(day, (7 + i % 12) * 60);
          final e = Event(title: 'Carga $i', start: start, end: start.add(const Duration(hours: 1)), createdAt: now, updatedAt: now);
          batch.insert('evento', e.toRow()..['busca'] = 'carga $i');
        }
        await batch.commit(noResult: true);
      });
}
