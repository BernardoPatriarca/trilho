// Aba Mais: categorias e tags, modelos, notificações, resumo diário,
// preferências, PIN, backup, onboarding e sobre.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../domain/dates.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider).value;
    Widget item(IconData icon, String title, String route, {String? subtitle}) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('MAIS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('Organização'),
          item(Icons.folder_outlined, 'Categorias', '/mais/categorias'),
          item(Icons.tag, 'Tags', '/mais/tags'),
          item(Icons.playlist_add_check, 'Modelos de checklist', '/mais/modelos'),
          item(Icons.search, 'Busca e filtros salvos', '/busca'),
          const SectionTitle('Avisos'),
          item(
            Icons.notifications_outlined,
            'Notificações',
            '/mais/notificacoes',
            subtitle: 'Permissões, diagnóstico e teste',
          ),
          item(
            Icons.wb_sunny_outlined,
            'Resumo diário',
            '/mais/resumo',
            subtitle: cfg == null
                ? null
                : (cfg.summaryEnabled ? 'Ligado, às ${minutesToHm(cfg.summaryMinutes)}' : 'Desligado'),
          ),
          const SectionTitle('App'),
          item(Icons.tune, 'Preferências', '/mais/preferencias', subtitle: 'Tema, início da semana, lembretes padrão'),
          item(Icons.lock_outline, 'PIN', '/mais/pin', subtitle: cfg?.pinEnabled ?? false ? 'Ligado' : 'Desligado'),
          item(
            Icons.backup_outlined,
            'Backup e exportação',
            '/mais/backup',
            subtitle: cfg?.lastBackup == null ? 'Nenhum backup ainda' : 'Último: ${dayMonthYear(cfg!.lastBackup!)}',
          ),
          item(Icons.school_outlined, 'Refazer a configuração inicial', '/mais/onboarding'),
          item(Icons.info_outline, 'Sobre', '/mais/sobre', subtitle: 'Trilho 1.0.1'),
        ],
      ),
    );
  }
}
