// Aba Mais: preferências e utilidades. Cada fase acrescenta suas entradas
// (categorias, modelos, notificações, backup, PIN...).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/widgets/common.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('MAIS')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const SectionTitle('Aparência'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Tema', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeMode>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                          value: ThemeMode.system, label: Text('Sistema')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Escuro')),
                      ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
                    ],
                    selected: {mode},
                    onSelectionChanged: (s) async {
                      await ref.read(configRepositoryProvider).set(
                          'tema',
                          switch (s.first) {
                            ThemeMode.dark => 'escuro',
                            ThemeMode.light => 'claro',
                            ThemeMode.system => 'sistema',
                          });
                      ref.dataChanged();
                    },
                  ),
                ),
              ],
            ),
          ),
          const SectionTitle('App'),
          AppCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Sobre'),
              subtitle: const Text('Trilho 1.0.0'),
              onTap: () => showAboutDialog(
                context: context,
                applicationName: 'Trilho',
                applicationVersion: '1.0.0',
                applicationLegalese:
                    'O caminho que mantém o seu dia no curso.\n'
                    'Agenda, calendário e tarefas, 100% offline.',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
