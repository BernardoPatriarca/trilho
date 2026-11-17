// Todas as abas e telas em 320 dp com fonte do sistema em 130%: falha em
// qualquer overflow. Rode ao mexer em layouts.
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/features/events/event_repository.dart';
import 'package:trilho/features/tasks/task_repository.dart';

import 'helpers.dart';

void main() {
  testWidgets('telas aguentam 320 dp com fonte 1,3x', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final db = await openWidgetDb();
    final now = fixedNow;
    late int taskId, eventId;
    {
      taskId = await TaskRepository(db).save(
        TaskDraft(
          task: Task(
            title: 'Ir ao mercado com um título bem comprido para testar quebra',
            dueDate: DateTime(2026, 11, 17),
            dueMinutes: 18 * 60,
            priority: 2,
            categoryId: 7,
            createdAt: now,
            updatedAt: now,
          ),
          checklist: const [
            ChecklistItem(text: 'óleo de soja', quantity: '2 un'),
            ChecklistItem(text: 'açúcar', checked: true),
          ],
          tagNames: const ['casa', 'semanal'],
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [2]),
        ),
        now: now,
      );
      await TaskRepository(db).save(
        TaskDraft(
          task: Task(title: 'Atrasada', dueDate: DateTime(2026, 11, 10), priority: 1, createdAt: now, updatedAt: now),
        ),
        now: now,
      );
      eventId = await EventRepository(db).save(
        EventDraft(
          event: Event(
            title: 'Reunião de alinhamento com o time inteiro',
            location: 'Sala 3',
            start: DateTime(2026, 11, 17, 14),
            end: DateTime(2026, 11, 17, 15),
            categoryId: 1,
            createdAt: now,
            updatedAt: now,
          ),
          rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [2]),
        ),
        now: now,
      );
    }

    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      final where = d.informationCollector?.call().map((e) => e.toString()).join('\n') ?? '';
      errors.add('${d.exceptionAsString()}\n${where.split('\n').take(6).join('\n')}');
    };
    addTearDown(() => FlutterError.onError = old);

    await pumpApp(tester, db);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));

    Future<void> visit(String label, Future<void> Function() go) async {
      await go();
      await settle(tester, 10);
      if (errors.isNotEmpty) {
        FlutterError.onError = old;
        debugPrint('Overflow em $label:\n${errors.map((e) => e.split('\n').take(2).join(' | ')).join('\n')}');
        fail('Overflow em $label: ${errors.first.split('\n').first}');
      }
    }

    for (final tab in const ['Agenda', 'Tarefas', 'Estatísticas', 'Mais', 'Hoje']) {
      await visit('aba $tab', () => tester.tap(find.text(tab).last));
    }
    for (final view in const ['Semana', 'Dia', 'Lista', 'Mês']) {
      await visit('aba Agenda', () => tester.tap(find.text('Agenda').last));
      await visit('Agenda › $view', () => tester.tap(find.text(view).last));
    }
    for (final route in [
      '/tarefa/$taskId',
      '/tarefa/nova',
      '/evento/$eventId?data=2026-11-17',
      '/evento/novo',
      '/busca',
      '/mais/categorias',
      '/mais/tags',
      '/mais/modelos',
      '/mais/notificacoes',
      '/mais/resumo',
      '/mais/preferencias',
      '/mais/pin',
      '/mais/backup',
      '/mais/sobre',
      '/mais/onboarding',
    ]) {
      await visit(route, () async {
        router.push(route);
      });
      router.pop();
      await settle(tester, 4);
    }
    await visit('adição rápida', () async {
      router.go('/hoje');
      await settle(tester, 4);
      await tester.tap(find.byKey(const Key('quickAddFab')));
      await settle(tester, 4);
      await tester.enterText(
        find.byKey(const Key('quickAddField')),
        'Mercado amanhã 18h #casa !2 @compras toda segunda',
      );
    });
  });
}
