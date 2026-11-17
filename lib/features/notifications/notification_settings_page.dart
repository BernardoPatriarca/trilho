// Mais › Notificações: configurações e diagnóstico (status de cada permissão
// com botão para corrigir, otimização de bateria com dicas por fabricante,
// "Testar lembrete em 1 minuto", próximas agendadas e "Reagendar tudo").
// Mais › Resumo diário: ligar/desligar e horário.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/form_fields.dart';
import '../../domain/dates.dart';
import '../settings/config_repository.dart';
import 'notification_scheduler.dart';
import 'system_settings.dart';

class PermissionStatus {
  const PermissionStatus({
    required this.notifications,
    required this.exact,
    required this.battery,
    required this.manufacturer,
  });
  final bool notifications;
  final bool exact;
  final bool battery;
  final String manufacturer;

  bool get allGood => notifications && exact && battery;
}

final permissionStatusProvider = FutureProvider.autoDispose<PermissionStatus>((ref) async {
  final local = ref.watch(localNotificationsProvider);
  final sys = ref.watch(systemSettingsProvider);
  if (local == null) {
    return const PermissionStatus(notifications: true, exact: true, battery: true, manufacturer: '');
  }
  return PermissionStatus(
    notifications: await local.notificationsEnabled(),
    exact: await local.canScheduleExact(),
    battery: await sys.ignoringBatteryOptimizations(),
    manufacturer: await sys.manufacturer(),
  );
});

final upcomingNotificationsProvider = FutureProvider.autoDispose<List<ScheduledRow>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(schedulerProvider).upcoming(limit: 50);
});

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends ConsumerState<NotificationSettingsPage> {
  late final AppLifecycleListener _life;

  @override
  void initState() {
    super.initState();
    // Voltou das configurações do sistema: confere de novo.
    _life = AppLifecycleListener(
      onResume: () {
        ref.invalidate(permissionStatusProvider);
        ref.resync();
      },
    );
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(permissionStatusProvider);
    await ref.resync();
    ref.invalidate(upcomingNotificationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = ref.watch(permissionStatusProvider);
    final upcoming = ref.watch(upcomingNotificationsProvider);
    final local = ref.watch(localNotificationsProvider);
    final sys = ref.watch(systemSettingsProvider);
    final error = ref.watch(lastSyncErrorProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('NOTIFICAÇÕES')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            const SectionTitle('Permissões'),
            AsyncView(
              status,
              builder: (s) {
                return Column(
                  children: [
                    _StatusTile(
                      ok: s.notifications,
                      title: 'Mostrar notificações',
                      okText: 'Permitido',
                      badText: 'Bloqueado: você não vai ver os lembretes.',
                      action: 'Permitir',
                      onFix: () async {
                        final granted = await local?.requestNotifications() ?? false;
                        if (!granted) await local?.openNotificationSettings();
                        await _refresh();
                      },
                    ),
                    _StatusTile(
                      ok: s.exact,
                      title: 'Alarmes e lembretes (horário exato)',
                      okText: 'Permitido: os lembretes tocam na hora certa.',
                      badText: 'Sem permissão: os lembretes usam horário aproximado e podem atrasar alguns minutos.',
                      action: 'Abrir configuração',
                      onFix: () async {
                        await local?.requestExactAlarms();
                        await _refresh();
                      },
                    ),
                    _StatusTile(
                      ok: s.battery,
                      title: 'Otimização de bateria',
                      okText: 'Desativada para o Trilho: ótimo.',
                      badText: 'Ativa: o sistema pode segurar os lembretes no modo econômico.',
                      action: 'Desativar',
                      onFix: () async {
                        await sys.requestIgnoreBatteryOptimizations();
                        await _refresh();
                      },
                    ),
                    if (!s.battery || batteryTips.containsKey(s.manufacturer))
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 8),
                        child: _BatteryTips(manufacturer: s.manufacturer),
                      ),
                  ],
                );
              },
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Último reagendamento falhou: $error', style: TextStyle(color: c.error)),
              ),
            const SectionTitle('Testes'),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final at = await ref.read(schedulerProvider).scheduleTest();
                      ref.invalidate(upcomingNotificationsProvider);
                      if (context.mounted) {
                        showSnack(context, 'Lembrete de teste às ${hm(at)}. Bloqueie o celular e espere.');
                      }
                    },
                    icon: const Icon(Icons.alarm_add),
                    label: const Text('Testar lembrete em 1 minuto'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final r = await ref.read(schedulerProvider).rescheduleAll();
                ref.read(dataRevisionProvider.notifier).bump();
                if (context.mounted) {
                  showSnack(context, '${r.total} notificações reagendadas${r.exact ? '' : ' (horário aproximado)'}');
                }
              },
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reagendar tudo'),
            ),
            const SectionTitle('Próximas notificações'),
            AsyncView(
              upcoming,
              builder: (rows) {
                if (rows.isEmpty) {
                  return Text('Nada agendado nos próximos 30 dias.', style: TextStyle(color: c.textSecondary));
                }
                return Column(
                  children: [
                    for (final r in rows)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: Icon(switch (r.kind) {
                          'resumo' => Icons.wb_sunny_outlined,
                          'backup' => Icons.backup_outlined,
                          'teste' => Icons.science_outlined,
                          _ => r.targetType == 'evento' ? Icons.event_outlined : Icons.check_circle_outline,
                        }),
                        title: Text(r.title ?? r.kind, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${weekdayShort[r.fireAt.weekday]}, ${dayMonth(r.fireAt)} às ${hm(r.fireAt)}',
                          style: const TextStyle(fontFeatures: tabular),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 8),
            Text(
              'O Trilho agenda os próximos 30 dias (no máximo 400 alarmes) e reagenda ao abrir o app, '
              'a cada mudança e depois de reiniciar o celular.',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({
    required this.ok,
    required this.title,
    required this.okText,
    required this.badText,
    required this.action,
    required this.onFix,
  });
  final bool ok;
  final String title;
  final String okText;
  final String badText;
  final String action;
  final VoidCallback onFix;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        child: Row(
          children: [
            Icon(
              ok ? Icons.check_circle : Icons.error_outline,
              color: ok ? c.success : c.warning,
              semanticLabel: ok ? 'OK' : 'Atenção',
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(ok ? okText : badText, style: TextStyle(fontSize: 13, color: c.textSecondary)),
                ],
              ),
            ),
            if (!ok) TextButton(onPressed: onFix, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class _BatteryTips extends StatelessWidget {
  const _BatteryTips({required this.manufacturer});
  final String manufacturer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final mine = batteryTips[manufacturer];
    return AppCard(
      color: c.surfaceHigh,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Dicas por fabricante', style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (mine != null) ...[
            Text('Seu aparelho:', style: TextStyle(fontSize: 12, color: c.textSecondary)),
            Text(mine),
            const SizedBox(height: 8),
          ],
          for (final e in batteryTips.entries.where((e) => e.key != manufacturer))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(e.value, style: TextStyle(fontSize: 13, color: c.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class SummarySettingsPage extends ConsumerWidget {
  const SummarySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final cfg = ref.watch(configProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('RESUMO DIÁRIO')),
      body: AsyncView(
        cfg,
        builder: (cfg) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              AppCard(
                padding: EdgeInsets.zero,
                child: SwitchListTile(
                  title: const Text('Receber o resumo do dia'),
                  subtitle: const Text('Uma notificação silenciosa com os eventos, as tarefas P1/P2 e as atrasadas'),
                  value: cfg.summaryEnabled,
                  onChanged: (v) async {
                    await ref.read(configRepositoryProvider).set(ConfigRepository.summaryEnabled, v ? '1' : '0');
                    ref.dataChanged();
                  },
                ),
              ),
              const SizedBox(height: 12),
              FieldButton(
                label: 'Horário',
                icon: Icons.schedule,
                value: minutesToHm(cfg.summaryMinutes),
                onTap: () async {
                  final m = await pickTime(context, cfg.summaryMinutes);
                  if (m == null) return;
                  await ref.read(configRepositoryProvider).set(ConfigRepository.summaryTime, minutesToHm(m));
                  ref.dataChanged();
                },
              ),
              const SizedBox(height: 16),
              Text(
                'Como o conteúdo de uma notificação agendada é fixo, o Trilho já deixa prontos os resumos dos próximos 7 dias '
                'e refaz os afetados sempre que algo muda nesses dias.',
                style: TextStyle(fontSize: 13, color: c.textSecondary),
              ),
            ],
          );
        },
      ),
    );
  }
}
