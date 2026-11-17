// Rotas: 5 abas (Hoje · Agenda · Tarefas · Estatísticas · Mais). Telas cheias
// (detalhe de tarefa, evento, busca...) entram com `_full`, por cima das abas.
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../features/calendar/agenda_page.dart';
import '../features/settings/more_page.dart';
import '../features/stats/stats_page.dart';
import '../features/tasks/tasks_page.dart';
import '../features/today/today_page.dart';
import 'shell.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

GoRouter buildRouter() => GoRouter(
      navigatorKey: rootNavigatorKey,
      initialLocation: '/hoje',
      routes: [
        StatefulShellRoute.indexedStack(
          builder: (context, state, shell) => AppShell(shell: shell),
          branches: [
            for (final (path, page) in const [
              ('/hoje', TodayPage()),
              ('/agenda', AgendaPage()),
              ('/tarefas', TasksPage()),
              ('/estatisticas', StatsPage()),
              ('/mais', MorePage()),
            ])
              StatefulShellBranch(routes: [
                GoRoute(path: path, builder: (_, _) => page),
              ]),
          ],
        ),
      ],
    );
