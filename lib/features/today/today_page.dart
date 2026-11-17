// Aba Hoje: data por extenso e, nas próximas fases, atrasadas, linha do tempo,
// tarefas do dia, fixadas e concluídas (regra 6.5).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/common.dart';

class TodayPage extends ConsumerWidget {
  const TodayPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('HOJE')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          Text(
            longDate(now),
            style: TextStyle(color: context.colors.textSecondary, fontSize: 16),
          ),
          const EmptyState(
            icon: Icons.wb_sunny_outlined,
            title: 'Nada para hoje',
            message: 'Toque em + para adicionar uma tarefa ou um evento.',
          ),
        ],
      ),
    );
  }
}
