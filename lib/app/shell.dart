// Shell com a barra de abas inferior e o FAB de adição rápida
// (presente em todas as abas, exceto Mais).
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/quick_add/quick_add_sheet.dart';

/// Índice da aba Mais (sem FAB).
const _moreTab = 4;

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    final showFab = shell.currentIndex != _moreTab;
    return Scaffold(
      body: shell,
      floatingActionButton: showFab
          ? FloatingActionButton(
              key: const Key('quickAddFab'),
              tooltip: 'Adição rápida',
              onPressed: () => showQuickAddSheet(context),
              child: const Icon(Icons.add, size: 28),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny), label: 'Hoje'),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Agenda',
          ),
          NavigationDestination(
            icon: Icon(Icons.check_circle_outline),
            selectedIcon: Icon(Icons.check_circle),
            label: 'Tarefas',
          ),
          NavigationDestination(
            icon: Icon(Icons.insights_outlined),
            selectedIcon: Icon(Icons.insights),
            label: 'Estatísticas',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'Mais'),
        ],
      ),
    );
  }
}
