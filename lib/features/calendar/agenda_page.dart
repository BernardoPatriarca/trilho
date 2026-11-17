// Aba Agenda: visões mês, semana, dia e lista (fase 5).
import 'package:material_ui/material_ui.dart';

import '../../core/widgets/common.dart';

class AgendaPage extends StatelessWidget {
  const AgendaPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AGENDA')),
      body: const EmptyState(
        icon: Icons.calendar_month_outlined,
        title: 'Agenda vazia',
        message: 'Seus eventos aparecem aqui. Toque em + para criar o primeiro.',
      ),
    );
  }
}
