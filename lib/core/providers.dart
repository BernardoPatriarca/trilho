// Providers de infraestrutura: banco, relógio, repositórios, notificações e
// a "revisão" dos dados.
//
// Toda escrita chama `ref.dataChanged()`: sobe a revisão (as telas que
// observam os dados recarregam sozinhas) e reagenda as notificações.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqflite/sqflite.dart';

import '../features/categories/category_repository.dart';
import '../features/events/event_repository.dart';
import '../features/notifications/notification_scheduler.dart';
import '../features/notifications/notification_service.dart';
import '../features/notifications/system_settings.dart';
import '../features/search/search_repository.dart';
import '../features/settings/backup_service.dart';
import '../features/settings/config_repository.dart';
import '../features/settings/pin_service.dart';
import '../features/tasks/task_repository.dart';
import '../features/templates/template_repository.dart';

/// Sobrescrito em `main.dart` (e nos testes) com o banco aberto.
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('databaseProvider não configurado'));

/// Relógio do app (sobrescrito nos testes para fixar "agora").
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

class DataRevision extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final dataRevisionProvider = NotifierProvider<DataRevision, int>(DataRevision.new);

final configRepositoryProvider = Provider((ref) => ConfigRepository(ref.watch(databaseProvider)));
final categoryRepositoryProvider = Provider((ref) => CategoryRepository(ref.watch(databaseProvider)));
final tagRepositoryProvider = Provider((ref) => TagRepository(ref.watch(databaseProvider)));
final taskRepositoryProvider = Provider((ref) => TaskRepository(ref.watch(databaseProvider)));
final eventRepositoryProvider = Provider((ref) => EventRepository(ref.watch(databaseProvider)));
final templateRepositoryProvider = Provider((ref) => TemplateRepository(ref.watch(databaseProvider)));
final searchRepositoryProvider = Provider((ref) => SearchRepository(ref.watch(databaseProvider)));
final backupServiceProvider = Provider((ref) => BackupService(ref.watch(databaseProvider)));

/// Plugin de notificações. Em `main.dart` vira o [LocalNotificationGateway].
final notificationGatewayProvider = Provider<NotificationGateway>((ref) => const NoopNotificationGateway());

/// O gateway real, quando existir (permissões e diagnóstico).
final localNotificationsProvider = Provider<LocalNotificationGateway?>((ref) {
  final g = ref.watch(notificationGatewayProvider);
  return g is LocalNotificationGateway ? g : null;
});

final schedulerProvider = Provider((ref) => NotificationScheduler(
      ref.watch(databaseProvider),
      ref.watch(notificationGatewayProvider),
      clock: ref.watch(clockProvider),
    ));

final systemSettingsProvider = Provider((ref) => const SystemSettings());

/// Onde o hash do PIN fica (armazenamento seguro; memória nos testes).
final pinStoreProvider = Provider<PinStore>((ref) => SecurePinStore());

final configProvider = FutureProvider<AppConfig>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(configRepositoryProvider).load();
});

/// Tema escolhido em Mais (config `tema`).
final themeModeProvider = Provider<ThemeMode>((ref) {
  final theme = ref.watch(configProvider).value?.theme ?? 'sistema';
  return switch (theme) {
    'escuro' => ThemeMode.dark,
    'claro' => ThemeMode.light,
    _ => ThemeMode.system,
  };
});

/// Erros do último reagendamento (mostrados no diagnóstico).
class SyncError extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

final lastSyncErrorProvider = NotifierProvider<SyncError, String?>(SyncError.new);

extension DataChanged on WidgetRef {
  /// Avisa que os dados mudaram: recarrega as telas e reagenda notificações.
  void dataChanged() {
    read(dataRevisionProvider.notifier).bump();
    unawaited(resync());
  }

  Future<void> resync() async {
    try {
      await read(schedulerProvider).sync();
      read(lastSyncErrorProvider.notifier).set(null);
    } on Object catch (e) {
      read(lastSyncErrorProvider.notifier).set('$e');
    }
  }

  DateTime now() => read(clockProvider)();
}
