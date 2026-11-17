// Rotas: 5 abas (Hoje · Agenda · Tarefas · Estatísticas · Mais) e telas
// cheias por cima da barra de abas.
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../domain/dates.dart';
import '../domain/search.dart';
import '../features/calendar/agenda_page.dart';
import '../features/categories/categories_page.dart';
import '../features/events/event_edit_page.dart';
import '../features/events/event_repository.dart';
import '../features/notifications/notification_settings_page.dart';
import '../features/search/search_page.dart';
import '../features/settings/backup_page.dart';
import '../features/settings/more_page.dart';
import '../features/settings/onboarding_page.dart';
import '../features/settings/settings_pages.dart';
import '../features/stats/stats_page.dart';
import '../features/tasks/task_edit_page.dart';
import '../features/tasks/task_repository.dart';
import '../features/tasks/tasks_page.dart';
import '../features/templates/templates_page.dart';
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
          StatefulShellBranch(
            routes: [GoRoute(path: path, builder: (_, _) => page)],
          ),
      ],
    ),
    _full('/tarefa/nova', (s) => TaskEditPage(initial: s.extra is TaskDraft ? s.extra! as TaskDraft : null)),
    _full(
      '/tarefa/:id',
      (s) => TaskEditPage(key: ValueKey(s.pathParameters['id']), taskId: int.tryParse(s.pathParameters['id']!)),
    ),
    _full(
      '/evento/novo',
      (s) => EventEditPage(
        initial: s.extra is EventDraft ? s.extra! as EventDraft : null,
        initialStart: s.extra is DateTime ? s.extra! as DateTime : null,
      ),
    ),
    _full('/evento/:id', (s) {
      final data = s.uri.queryParameters['data'];
      return EventEditPage(
        key: ValueKey('${s.pathParameters['id']}-$data'),
        eventId: int.tryParse(s.pathParameters['id']!),
        occurrenceDate: data == null ? null : fromIsoDate(data),
      );
    }),
    _full('/busca', (s) => SearchPage(initial: s.extra is SearchCriteria ? s.extra! as SearchCriteria : null)),
    _full('/onboarding', (_) => const OnboardingPage()),
    _full('/mais/onboarding', (_) => const OnboardingPage(fromSettings: true)),
    _full('/mais/categorias', (_) => const CategoriesPage()),
    _full('/mais/tags', (_) => const TagsPage()),
    _full('/mais/modelos', (_) => const TemplatesPage()),
    _full('/mais/notificacoes', (_) => const NotificationSettingsPage()),
    _full('/mais/resumo', (_) => const SummarySettingsPage()),
    _full('/mais/preferencias', (_) => const PreferencesPage()),
    _full('/mais/pin', (_) => const PinSettingsPage()),
    _full('/mais/backup', (_) => const BackupPage()),
    _full('/mais/sobre', (_) => const AboutPage()),
  ],
);

GoRoute _full(String path, Widget Function(GoRouterState) build) =>
    GoRoute(path: path, parentNavigatorKey: rootNavigatorKey, builder: (_, state) => build(state));

/// Payload da notificação → rota.
String? routeForPayload(String? payload) {
  if (payload == null) return null;
  if (payload == 'hoje') return '/hoje';
  if (payload == 'backup') return '/mais/backup';
  if (payload == 'diagnostico') return '/mais/notificacoes';
  final parts = payload.split(':');
  if (parts.first == 'tarefa' && parts.length >= 2) return '/tarefa/${parts[1]}';
  if (parts.first == 'evento' && parts.length >= 2) {
    return parts.length >= 3 ? '/evento/${parts[1]}?data=${parts[2]}' : '/evento/${parts[1]}';
  }
  return null;
}
