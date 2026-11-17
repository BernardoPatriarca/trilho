// Configurações (tabela `config`, chave/valor).
import 'package:sqflite/sqflite.dart';

import '../../domain/dates.dart';

/// Retrato das configurações, já com tipos.
class AppConfig {
  const AppConfig(this.raw);
  final Map<String, String> raw;

  bool get summaryEnabled => raw['resumo_ativo'] != '0';
  int get summaryMinutes => hmToMinutes(raw['resumo_hora']) ?? 7 * 60;
  bool get mondayFirst => raw['inicio_semana'] != 'domingo';
  int get defaultEventReminder => int.tryParse(raw['lembrete_padrao_evento_min'] ?? '') ?? 15;
  int get defaultTaskMinutes => hmToMinutes(raw['lembrete_padrao_tarefa_hora']) ?? 9 * 60;
  int get postponeMinutes => int.tryParse(raw['adiar_padrao_min'] ?? '') ?? 60;

  /// `sistema`, `escuro` ou `claro`.
  String get theme => raw['tema'] ?? 'sistema';
  bool get pinEnabled => raw['pin_ativo'] == '1';
  bool get onboarded => raw['onboarding_concluido'] == '1';
  bool get showTasksInCalendar => raw['mostrar_tarefas_calendario'] != '0';
  bool get weeklyBackupReminder => raw['backup_semanal'] == '1';
  DateTime? get lastBackup {
    final v = raw['ultimo_backup'];
    return v == null ? null : DateTime.tryParse(v);
  }
}

class ConfigRepository {
  ConfigRepository(this.db);
  final Database db;

  static const summaryEnabled = 'resumo_ativo';
  static const summaryTime = 'resumo_hora';
  static const weekStart = 'inicio_semana';
  static const defaultEventReminder = 'lembrete_padrao_evento_min';
  static const defaultTaskTime = 'lembrete_padrao_tarefa_hora';
  static const postponeDefault = 'adiar_padrao_min';
  static const theme = 'tema';
  static const pinEnabled = 'pin_ativo';
  static const onboarded = 'onboarding_concluido';
  static const showTasksInCalendar = 'mostrar_tarefas_calendario';
  static const weeklyBackup = 'backup_semanal';
  static const lastBackup = 'ultimo_backup';

  Future<String?> get(String key) async {
    final rows = await db.query('config', where: 'chave = ?', whereArgs: [key]);
    return rows.isEmpty ? null : rows.first['valor'] as String;
  }

  Future<void> set(String key, String value, {DatabaseExecutor? txn}) =>
      (txn ?? db).insert('config', {'chave': key, 'valor': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<AppConfig> load() async {
    final rows = await db.query('config');
    return AppConfig({for (final r in rows) r['chave'] as String: r['valor'] as String});
  }
}
