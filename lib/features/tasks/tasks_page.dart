// Aba Tarefas: lista com filtros, agrupamento e ordenação manual (fase 4).
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/common.dart';

class TasksPage extends StatelessWidget {
  const TasksPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TAREFAS')),
      body: const EmptyState(
        icon: Icons.checklist_rounded,
        title: 'Nenhuma tarefa',
        message: 'Toque em + e escreva, por exemplo, "Mercado amanhã 18h".',
      ),
    );
  }
}
