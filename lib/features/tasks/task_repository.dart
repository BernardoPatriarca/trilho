// Tarefas: CRUD, checklist, tags, lembretes, recorrência, concluir e adiar.
import 'package:sqflite/sqflite.dart';

import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/tasks.dart';
import '../../domain/text.dart';
import '../categories/category_repository.dart';

class TaskDetails {
  const TaskDetails({
    required this.task,
    this.checklist = const [],
    this.tags = const [],
    this.reminders = const [],
    this.rule,
  });
  final Task task;
  final List<ChecklistItem> checklist;
  final List<Tag> tags;
  final List<Reminder> reminders;
  final RecurrenceRule? rule;
}

/// O que o formulário (ou a adição rápida) manda salvar.
class TaskDraft {
  const TaskDraft({
    required this.task,
    this.checklist = const [],
    this.tagNames = const [],
    this.reminders = const [],
    this.rule,
    this.remindersTouched = false,
  });
  final Task task;
  final List<ChecklistItem> checklist;
  final List<String> tagNames;
  final List<Reminder> reminders;
  final RecurrenceRule? rule;

  /// O usuário mexeu nos lembretes (então não aplica o lembrete padrão).
  final bool remindersTouched;
}

/// Tudo o que as listas precisam, numa leitura só.
class TaskListData {
  const TaskListData({
    this.tasks = const [],
    this.progress = const {},
    this.tagIds = const {},
    this.recurrenceRules = const {},
  });
  final List<Task> tasks;
  final Map<int, ChecklistProgress> progress;
  final Map<int, Set<int>> tagIds;
  final Map<int, RecurrenceRule> recurrenceRules;

  ChecklistProgress progressOf(Task t) => progress[t.id] ?? ChecklistProgress.empty;
}

class CompletionResult {
  const CompletionResult({required this.before, this.nextId});
  final Task before;

  /// Próxima instância criada (tarefa recorrente).
  final int? nextId;
}

class ValidationException implements Exception {
  ValidationException(this.message);
  final String message;
  @override
  String toString() => message;
}

class TaskRepository {
  TaskRepository(this.db) : tags = TagRepository(db);
  final Database db;
  final TagRepository tags;

  Future<TaskListData> listData() async {
    final rows = await db.query('tarefa');
    final tasks = rows.map(Task.fromRow).toList();
    final prog = await db.rawQuery(
      'SELECT tarefa_id, SUM(marcado) AS m, COUNT(*) AS n FROM checklist_item GROUP BY tarefa_id',
    );
    final tagRows = await db.query('tarefa_tag');
    final tagIds = <int, Set<int>>{};
    for (final r in tagRows) {
      tagIds.putIfAbsent(r['tarefa_id'] as int, () => {}).add(r['tag_id'] as int);
    }
    final rules = await db.rawQuery(
      'SELECT r.* FROM recorrencia r WHERE r.id IN (SELECT recorrencia_id FROM tarefa WHERE recorrencia_id IS NOT NULL)',
    );
    return TaskListData(
      tasks: tasks,
      progress: {for (final r in prog) r['tarefa_id'] as int: ChecklistProgress((r['m'] as int?) ?? 0, r['n'] as int)},
      tagIds: tagIds,
      recurrenceRules: {for (final r in rules) r['id'] as int: RecurrenceRule.fromRow(r)},
    );
  }

  /// Índice de busca (título + descrição + checklist) de cada tarefa.
  Future<Map<int, String>> searchIndexes() async {
    final rows = await db.query('tarefa', columns: ['id', 'busca']);
    return {for (final r in rows) r['id'] as int: r['busca'] as String};
  }

  Future<TaskDetails?> get(int id) async {
    final rows = await db.query('tarefa', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return null;
    final task = Task.fromRow(rows.first);
    return TaskDetails(
      task: task,
      checklist: await checklist(id),
      tags: (await db.rawQuery(
        'SELECT t.* FROM tag t JOIN tarefa_tag tt ON tt.tag_id = t.id WHERE tt.tarefa_id = ? ORDER BY t.nome',
        [id],
      )).map(Tag.fromRow).toList(),
      reminders: await reminders(id),
      rule: task.recurrenceId == null ? null : await _rule(db, task.recurrenceId!),
    );
  }

  Future<List<ChecklistItem>> checklist(int taskId, {DatabaseExecutor? txn}) async => (await (txn ?? db).query(
    'checklist_item',
    where: 'tarefa_id = ?',
    whereArgs: [taskId],
    orderBy: 'ordem, id',
  )).map(ChecklistItem.fromRow).toList();

  Future<List<Reminder>> reminders(int taskId, {DatabaseExecutor? txn}) async => (await (txn ?? db).query(
    'lembrete',
    where: "alvo_tipo = 'tarefa' AND alvo_id = ?",
    whereArgs: [taskId],
    orderBy: 'id',
  )).map(Reminder.fromRow).toList();

  Future<RecurrenceRule?> _rule(DatabaseExecutor ex, int id) async {
    final r = await ex.query('recorrencia', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : RecurrenceRule.fromRow(r.first);
  }

  /// Salva a tarefa inteira. Retorna o id. Lança [ValidationException].
  Future<int> save(TaskDraft d, {required DateTime now}) async {
    final t = d.task;
    final error =
        validateTask(title: t.title, dueDate: t.dueDate, dueMinutes: t.dueMinutes, rule: d.rule) ??
        (t.dueDate == null ? null : validateRule(d.rule, t.dueDate!));
    if (error != null) throw ValidationException(error);

    return db.transaction((txn) async {
      final isNew = t.id == null;
      int? recId = t.recurrenceId;
      if (d.rule != null) {
        if (recId != null) {
          await txn.update('recorrencia', d.rule!.toRow(), where: 'id = ?', whereArgs: [recId]);
        } else {
          recId = await txn.insert('recorrencia', d.rule!.toRow());
        }
      }
      var task = t.copyWith(
        title: t.title.trim(),
        recurrenceId: recId,
        clearRecurrence: d.rule == null,
        updatedAt: now,
        createdAt: isNew ? now : t.createdAt,
      );
      final row = task.toRow()
        ..['busca'] = searchIndex([task.title, task.description, ...d.checklist.map((i) => i.text)]);
      late int id;
      if (isNew) {
        if (row['ordem'] == 0) {
          row['ordem'] = (await txn.rawQuery('SELECT COALESCE(MAX(ordem), 0) + 1 AS o FROM tarefa')).first['o'] as int;
        }
        id = await txn.insert('tarefa', row);
      } else {
        id = t.id!;
        await txn.update('tarefa', row, where: 'id = ?', whereArgs: [id]);
      }
      // Regra removida: apaga a linha órfã.
      if (d.rule == null && t.recurrenceId != null) {
        await _deleteRuleIfUnused(txn, t.recurrenceId!);
      }

      await _replaceChecklist(txn, id, d.checklist);

      await txn.delete('tarefa_tag', where: 'tarefa_id = ?', whereArgs: [id]);
      for (final tagId in await tags.idsFor(d.tagNames, txn: txn)) {
        await txn.insert('tarefa_tag', {'tarefa_id': id, 'tag_id': tagId});
      }

      var reminders = d.reminders;
      // Lembrete padrão: na hora do prazo (ou às 9h para tarefas só com data).
      if (isNew && !d.remindersTouched && reminders.isEmpty && task.dueDate != null) {
        reminders = const [Reminder.relative(0)];
      }
      await _replaceReminders(txn, TargetType.tarefa, id, reminders);
      return id;
    });
  }

  Future<void> _replaceChecklist(Transaction txn, int taskId, List<ChecklistItem> items) async {
    final keep = items.where((i) => i.id != null).map((i) => i.id!).toList();
    if (keep.isEmpty) {
      await txn.delete('checklist_item', where: 'tarefa_id = ?', whereArgs: [taskId]);
    } else {
      await txn.delete(
        'checklist_item',
        where: 'tarefa_id = ? AND id NOT IN (${List.filled(keep.length, '?').join(',')})',
        whereArgs: [taskId, ...keep],
      );
    }
    for (final (i, it) in items.indexed) {
      final row = {
        'tarefa_id': taskId,
        'texto': it.text.trim(),
        'quantidade': (it.quantity?.trim().isEmpty ?? true) ? null : it.quantity!.trim(),
        'marcado': it.checked ? 1 : 0,
        'ordem': i,
      };
      if (it.id == null) {
        await txn.insert('checklist_item', row);
      } else {
        await txn.update('checklist_item', row, where: 'id = ?', whereArgs: [it.id]);
      }
    }
  }

  static Future<void> _replaceReminders(DatabaseExecutor ex, TargetType type, int id, List<Reminder> reminders) async {
    await ex.delete('lembrete', where: 'alvo_tipo = ? AND alvo_id = ?', whereArgs: [type.name, id]);
    final seen = <String>{};
    for (final r in reminders) {
      if (!seen.add('${r.offsetMin}|${r.at}')) continue;
      await ex.insert('lembrete', r.toRow(type, id));
    }
  }

  static Future<void> replaceReminders(DatabaseExecutor ex, TargetType type, int id, List<Reminder> r) =>
      _replaceReminders(ex, type, id, r);

  Future<void> _deleteRuleIfUnused(DatabaseExecutor ex, int ruleId) async {
    final used = await ex.rawQuery(
      'SELECT (SELECT COUNT(*) FROM tarefa WHERE recorrencia_id = ?) + (SELECT COUNT(*) FROM evento WHERE recorrencia_id = ?) AS n',
      [ruleId, ruleId],
    );
    if ((used.first['n'] as int) == 0) await ex.delete('recorrencia', where: 'id = ?', whereArgs: [ruleId]);
  }

  /// Conclui. Se for recorrente, cria a próxima instância (prazo calculado a
  /// partir do prazo original, checklist desmarcada, tags e lembretes copiados).
  Future<CompletionResult> complete(int id, DateTime now) => db.transaction((txn) async {
    final rows = await txn.query('tarefa', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) throw ValidationException('Tarefa não encontrada.');
    final before = Task.fromRow(rows.first);
    if (!before.isPending) return CompletionResult(before: before);
    await txn.update(
      'tarefa',
      {
        'status': TaskStatus.concluida.name,
        'concluida_em': toIsoDateTime(now),
        'atualizada_em': toIsoDateTime(now),
        'fixada_hoje': 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    int? nextId;
    final rule = before.recurrenceId == null ? null : await _rule(txn, before.recurrenceId!);
    if (rule != null) {
      final nextDue = nextDueDate(before, rule);
      if (nextDue != null) {
        final newRuleId = await txn.insert('recorrencia', nextInstanceRule(rule).toRow());
        final next = nextInstance(before, nextDue, now, newRuleId);
        final items = resetChecklist(await checklist(id, txn: txn));
        final busca = (await txn.query('tarefa', columns: ['busca'], where: 'id = ?', whereArgs: [id])).first['busca'];
        nextId = await txn.insert('tarefa', next.toRow()..['busca'] = busca);
        for (final it in items) {
          await txn.insert('checklist_item', {
            'tarefa_id': nextId,
            'texto': it.text,
            'quantidade': it.quantity,
            'marcado': 0,
            'ordem': it.order,
          });
        }
        await txn.rawInsert(
          'INSERT INTO tarefa_tag (tarefa_id, tag_id) SELECT ?, tag_id FROM tarefa_tag WHERE tarefa_id = ?',
          [nextId, id],
        );
        final rem = shiftReminders(await reminders(id, txn: txn), before.dueDate!, nextDue);
        await _replaceReminders(txn, TargetType.tarefa, nextId, rem);
      }
    }
    return CompletionResult(before: before, nextId: nextId);
  });

  /// Desfaz uma conclusão (inclusive a próxima instância criada).
  Future<void> undoComplete(CompletionResult r) => db.transaction((txn) async {
    if (r.nextId != null) {
      final rec = await txn.query('tarefa', columns: ['recorrencia_id'], where: 'id = ?', whereArgs: [r.nextId]);
      await txn.delete('lembrete', where: "alvo_tipo = 'tarefa' AND alvo_id = ?", whereArgs: [r.nextId]);
      await txn.delete('tarefa', where: 'id = ?', whereArgs: [r.nextId]);
      final recId = rec.isEmpty ? null : rec.first['recorrencia_id'] as int?;
      if (recId != null) await _deleteRuleIfUnused(txn, recId);
    }
    await txn.update('tarefa', _statusRow(r.before), where: 'id = ?', whereArgs: [r.before.id]);
  });

  Map<String, Object?> _statusRow(Task t) => {
    'status': t.status.name,
    'concluida_em': t.completedAt == null ? null : toIsoDateTime(t.completedAt!),
    'atualizada_em': toIsoDateTime(t.updatedAt),
    'fixada_hoje': t.pinnedToday ? 1 : 0,
    'data_prazo': t.dueDate == null ? null : toIsoDate(t.dueDate!),
    'hora_prazo': t.dueDate == null || t.dueMinutes == null ? null : minutesToHm(t.dueMinutes!),
    'adiamentos': t.postponements,
  };

  /// Reabre uma tarefa concluída ou cancelada.
  Future<void> reopen(int id, DateTime now) => db.update(
    'tarefa',
    {'status': TaskStatus.pendente.name, 'concluida_em': null, 'atualizada_em': toIsoDateTime(now)},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<void> cancel(int id, DateTime now) => db.update(
    'tarefa',
    {'status': TaskStatus.cancelada.name, 'atualizada_em': toIsoDateTime(now), 'fixada_hoje': 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Novo prazo (regra 4). Retorna a tarefa como era, para desfazer.
  Future<Task> postponeTo(int id, DateTime date, int? minutes, DateTime now) async {
    final rows = await db.query('tarefa', where: 'id = ?', whereArgs: [id]);
    final before = Task.fromRow(rows.first);
    final after = postpone(before, date, minutes, now);
    await db.update('tarefa', _statusRow(after), where: 'id = ?', whereArgs: [id]);
    return before;
  }

  /// Volta prazo, status e adiamentos ao estado de [before] (desfazer).
  Future<void> restore(Task before) => db.update('tarefa', _statusRow(before), where: 'id = ?', whereArgs: [before.id]);

  /// "Reagendar tudo para hoje": atrasadas vão para hoje (a hora some se já
  /// passou, para não continuarem atrasadas). Retorna as tarefas antes.
  Future<List<Task>> rescheduleOverdueToToday(DateTime now) async {
    final all = (await db.query('tarefa', where: "status = 'pendente' AND data_prazo IS NOT NULL")).map(Task.fromRow);
    final overdue = all.where((t) => isOverdue(t, now)).toList();
    await db.transaction((txn) async {
      for (final t in overdue) {
        final keepTime = t.dueMinutes != null && t.dueMinutes! > minutesOfDay(now);
        final after = postpone(t, dateOnly(now), keepTime ? t.dueMinutes : null, now);
        await txn.update('tarefa', _statusRow(after), where: 'id = ?', whereArgs: [t.id]);
      }
    });
    return overdue;
  }

  Future<void> restoreAll(List<Task> before) => db.transaction((txn) async {
    for (final t in before) {
      await txn.update('tarefa', _statusRow(t), where: 'id = ?', whereArgs: [t.id]);
    }
  });

  Future<void> setPinned(int id, bool pinned, DateTime now) => db.update(
    'tarefa',
    {'fixada_hoje': pinned ? 1 : 0, 'atualizada_em': toIsoDateTime(now)},
    where: 'id = ?',
    whereArgs: [id],
  );

  /// Marca/desmarca um item já salvo. Retorna o progresso novo da tarefa.
  Future<ChecklistProgress> setItemChecked(int itemId, bool checked) async {
    await db.update('checklist_item', {'marcado': checked ? 1 : 0}, where: 'id = ?', whereArgs: [itemId]);
    final r = await db.rawQuery(
      'SELECT SUM(marcado) AS m, COUNT(*) AS n FROM checklist_item WHERE tarefa_id = (SELECT tarefa_id FROM checklist_item WHERE id = ?)',
      [itemId],
    );
    return ChecklistProgress((r.first['m'] as int?) ?? 0, (r.first['n'] as int?) ?? 0);
  }

  /// Ordem manual (lista arrastada).
  Future<void> reorder(List<int> ids) => db.transaction((txn) async {
    for (final (i, id) in ids.indexed) {
      await txn.update('tarefa', {'ordem': i + 1}, where: 'id = ?', whereArgs: [id]);
    }
  });

  Future<void> delete(int id) => db.transaction((txn) async {
    final rows = await txn.query('tarefa', columns: ['recorrencia_id'], where: 'id = ?', whereArgs: [id]);
    await txn.delete('lembrete', where: "alvo_tipo = 'tarefa' AND alvo_id = ?", whereArgs: [id]);
    await txn.delete('tarefa', where: 'id = ?', whereArgs: [id]);
    final recId = rows.isEmpty ? null : rows.first['recorrencia_id'] as int?;
    if (recId != null) await _deleteRuleIfUnused(txn, recId);
  });
}
