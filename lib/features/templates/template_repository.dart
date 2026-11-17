// Modelos de checklist reutilizáveis (ex.: "Mercado").
import 'package:sqflite/sqflite.dart';

import '../../domain/models.dart';

class TemplateRepository {
  TemplateRepository(this.db);
  final Database db;

  Future<List<ChecklistTemplate>> all() async {
    final heads = await db.query('modelo_checklist', orderBy: 'nome');
    final items = await db.query('modelo_checklist_item', orderBy: 'ordem, id');
    final byId = <int, List<ChecklistItem>>{};
    for (final r in items) {
      byId
          .putIfAbsent(r['modelo_id'] as int, () => [])
          .add(
            ChecklistItem(text: r['texto'] as String, quantity: r['quantidade'] as String?, order: r['ordem'] as int),
          );
    }
    return [
      for (final h in heads)
        ChecklistTemplate(id: h['id'] as int, name: h['nome'] as String, items: byId[h['id']] ?? const []),
    ];
  }

  /// Cria ou atualiza (por id). Nome repetido lança [ArgumentError].
  Future<int> save(ChecklistTemplate t) async {
    final name = t.name.trim();
    if (name.isEmpty) throw ArgumentError('Informe o nome do modelo.');
    final clash = await db.query(
      'modelo_checklist',
      where: 'nome = ? COLLATE NOCASE AND id <> ?',
      whereArgs: [name, t.id ?? -1],
    );
    if (clash.isNotEmpty) throw ArgumentError('Já existe um modelo com esse nome.');
    return db.transaction((txn) async {
      final id = t.id ?? await txn.insert('modelo_checklist', {'nome': name});
      if (t.id != null) {
        await txn.update('modelo_checklist', {'nome': name}, where: 'id = ?', whereArgs: [id]);
        await txn.delete('modelo_checklist_item', where: 'modelo_id = ?', whereArgs: [id]);
      }
      for (final (i, it) in t.items.indexed) {
        if (it.text.trim().isEmpty) continue;
        await txn.insert('modelo_checklist_item', {
          'modelo_id': id,
          'texto': it.text.trim(),
          'quantidade': (it.quantity?.trim().isEmpty ?? true) ? null : it.quantity!.trim(),
          'ordem': i,
        });
      }
      return id;
    });
  }

  Future<void> delete(int id) => db.delete('modelo_checklist', where: 'id = ?', whereArgs: [id]);
}
