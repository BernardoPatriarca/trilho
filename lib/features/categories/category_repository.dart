// Categorias e tags.
import 'package:sqflite/sqflite.dart';

import '../../domain/models.dart';
import '../../domain/text.dart';

class CategoryRepository {
  CategoryRepository(this.db);
  final Database db;

  Future<List<Category>> all({bool includeInactive = true}) async {
    final rows = await db.query('categoria', where: includeInactive ? null : 'ativo = 1', orderBy: 'ordem, nome');
    return rows.map(Category.fromRow).toList();
  }

  /// Lança [ArgumentError] com mensagem em português se o nome já existe.
  Future<int> save(Category c) async {
    final name = c.name.trim();
    if (name.isEmpty) throw ArgumentError('Informe o nome da categoria.');
    final clash = await db.query(
      'categoria',
      where: 'nome = ? COLLATE NOCASE AND id <> ?',
      whereArgs: [name, c.id ?? -1],
    );
    if (clash.isNotEmpty) throw ArgumentError('Já existe uma categoria com esse nome.');
    final row = c.copyWith(name: name).toRow();
    if (c.id == null) {
      final max = (await db.rawQuery('SELECT COALESCE(MAX(ordem), -1) + 1 AS o FROM categoria')).first['o'] as int;
      row['ordem'] = max;
      return db.insert('categoria', row);
    }
    await db.update('categoria', row, where: 'id = ?', whereArgs: [c.id]);
    return c.id!;
  }

  Future<void> setActive(int id, bool active) =>
      db.update('categoria', {'ativo': active ? 1 : 0}, where: 'id = ?', whereArgs: [id]);

  Future<void> reorder(List<int> ids) => db.transaction((txn) async {
    for (final (i, id) in ids.indexed) {
      await txn.update('categoria', {'ordem': i}, where: 'id = ?', whereArgs: [id]);
    }
  });
}

class TagRepository {
  TagRepository(this.db);
  final Database db;

  Future<List<Tag>> all() async => (await db.query('tag', orderBy: 'nome')).map(Tag.fromRow).toList();

  /// Quantos itens usam cada tag.
  Future<Map<int, int>> usage() async {
    final rows = await db.rawQuery('''
      SELECT t.id, (SELECT COUNT(*) FROM tarefa_tag WHERE tag_id = t.id)
                 + (SELECT COUNT(*) FROM evento_tag WHERE tag_id = t.id) AS n
      FROM tag t''');
    return {for (final r in rows) r['id'] as int: r['n'] as int};
  }

  /// Ids das tags com esses nomes, criando as que não existem.
  Future<List<int>> idsFor(Iterable<String> names, {DatabaseExecutor? txn}) async {
    final ex = txn ?? db;
    final ids = <int>[];
    for (final raw in names) {
      final name = normalizeTagName(raw);
      if (name.isEmpty) continue;
      final found = await ex.query('tag', where: 'nome = ?', whereArgs: [name]);
      ids.add(found.isNotEmpty ? found.first['id'] as int : await ex.insert('tag', {'nome': name}));
    }
    return ids.toSet().toList();
  }

  Future<void> rename(int id, String newName) async {
    final name = normalizeTagName(newName);
    if (name.isEmpty) throw ArgumentError('Informe o nome da tag.');
    final clash = await db.query('tag', where: 'nome = ? AND id <> ?', whereArgs: [name, id]);
    if (clash.isNotEmpty) throw ArgumentError('Já existe a tag #$name. Use "Mesclar".');
    await db.update('tag', {'nome': name}, where: 'id = ?', whereArgs: [id]);
  }

  /// Move tudo de [fromId] para [intoId] e apaga [fromId].
  Future<void> merge(int fromId, int intoId) => db.transaction((txn) async {
    await txn.rawInsert(
      'INSERT OR IGNORE INTO tarefa_tag (tarefa_id, tag_id) SELECT tarefa_id, ? FROM tarefa_tag WHERE tag_id = ?',
      [intoId, fromId],
    );
    await txn.rawInsert(
      'INSERT OR IGNORE INTO evento_tag (evento_id, tag_id) SELECT evento_id, ? FROM evento_tag WHERE tag_id = ?',
      [intoId, fromId],
    );
    await txn.delete('tag', where: 'id = ?', whereArgs: [fromId]);
  });

  Future<void> delete(int id) => db.delete('tag', where: 'id = ?', whereArgs: [id]);
}
