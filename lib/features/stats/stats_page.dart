// Aba Estatísticas: produtividade por período (fase 9).
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/common.dart';

class StatsPage extends StatelessWidget {
  const StatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESTATÍSTICAS')),
      body: const EmptyState(
        icon: Icons.insights_outlined,
        title: 'Ainda sem números',
        message: 'Conclua algumas tarefas e as estatísticas aparecem aqui.',
      ),
    );
  }
}
