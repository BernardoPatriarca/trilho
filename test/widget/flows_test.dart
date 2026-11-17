// Fluxos principais: adição rápida, marcar item de checklist e concluir
// tarefa com desfazer. Também onboarding e PIN.
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/domain/notification_plan.dart';
import 'package:trilho/features/settings/config_repository.dart';
import 'package:trilho/features/settings/pin_service.dart';
import 'package:trilho/features/tasks/task_edit_page.dart';
import 'package:trilho/features/tasks/task_repository.dart';

import 'helpers.dart';

void main() {
  testWidgets('adição rápida reconhece em chips e cria a tarefa com lembrete', (tester) async {
    final db = await openWidgetDb();
    final gw = await pumpApp(tester, db);

    await tester.tap(find.byKey(const Key('quickAddFab')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('quickAddField')), 'Mercado amanhã 18h @compras !2 #casa');
    await settle(tester, 4);

    expect(find.byKey(const Key('chip-date')), findsOneWidget);
    expect(find.text('18:00'), findsOneWidget);
    expect(find.text('@Compras'), findsOneWidget);
    expect(find.text('P2 · Alta'), findsOneWidget);
    expect(find.text('#casa'), findsOneWidget);

    await tester.tap(find.byKey(const Key('quickAddSave')));
    await settle(tester);

    final data = await TaskRepository(db).listData();
    final t = data.tasks.single;
    expect(t.title, 'Mercado');
    expect(t.dueDate, DateTime(2026, 11, 18));
    expect(t.dueMinutes, 18 * 60);
    expect(t.priority, 2);
    expect(t.categoryId, 7);
    expect(find.textContaining('Tarefa criada'), findsOneWidget);
    // Reagendou: lembrete na hora do prazo.
    await settle(tester, 4);
    expect(gw.ofKind(PlannedKind.lembrete).single.fireAt, DateTime(2026, 11, 18, 18));
  });

  testWidgets('remover um chip devolve o texto ao título', (tester) async {
    final db = await openWidgetDb();
    await pumpApp(tester, db);
    await tester.tap(find.byKey(const Key('quickAddFab')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('quickAddField')), 'Ligar hoje');
    await settle(tester, 4);
    await tester.tap(find.byTooltip('Não reconhecer "hoje"'));
    await settle(tester, 4);
    expect(find.byKey(const Key('chip-date')), findsNothing);
    expect(find.text('Ligar hoje'), findsWidgets);
  });

  testWidgets('marcar item da checklist grava na hora e pergunta se conclui ao marcar todos', (tester) async {
    final db = await openWidgetDb();
    final repo = TaskRepository(db);
    final id = await repo.save(
      TaskDraft(
        task: Task(title: 'Ir ao mercado', dueDate: DateTime(2026, 11, 17), createdAt: fixedNow, updatedAt: fixedNow),
        checklist: const [
          ChecklistItem(text: 'óleo'),
          ChecklistItem(text: 'açúcar', checked: true),
        ],
      ),
      now: fixedNow,
    );
    await pumpApp(tester, db);
    expect(find.text('1/2'), findsOneWidget); // progresso na tela Hoje

    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    router.push('/tarefa/$id');
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('óleo'),
      250,
      scrollable: find.descendant(of: find.byType(TaskEditPage), matching: find.byType(Scrollable)).first,
    );
    await tester.pump();
    await tester.tap(find.text('óleo'));
    await settle(tester);
    expect((await repo.checklist(id)).every((i) => i.checked), isTrue);
    expect(find.text('Concluir a tarefa também?'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await settle(tester);
    expect((await repo.get(id))!.task.isPending, isTrue);
  });

  testWidgets('concluir pela tela Hoje com desfazer', (tester) async {
    final db = await openWidgetDb();
    final repo = TaskRepository(db);
    final id = await repo.save(
      TaskDraft(
        task: Task(
          title: 'Prender o varão na parede',
          dueDate: DateTime(2026, 11, 17),
          createdAt: fixedNow,
          updatedAt: fixedNow,
        ),
      ),
      now: fixedNow,
    );
    await pumpApp(tester, db);

    await tester.tap(find.byKey(Key('check-$id')).first);
    await settle(tester);
    expect((await repo.get(id))!.task.isDone, isTrue);
    expect(find.text('Concluída: Prender o varão na parede'), findsOneWidget);
    expect(find.text('1 de 1 concluída'), findsOneWidget);

    await tester.tap(find.text('Desfazer'));
    await settle(tester);
    expect((await repo.get(id))!.task.isPending, isTrue);
    expect(find.text('0 de 1 concluída'), findsOneWidget);
  });

  testWidgets('onboarding na primeira execução e pular tudo', (tester) async {
    final db = await openWidgetDb(onboarded: false);
    await pumpApp(tester, db);
    expect(find.text('BEM-VINDO AO TRILHO'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboardingNext')));
    await settle(tester);
    expect(find.text('LEMBRETES DE VERDADE'), findsOneWidget);
    await tester.tap(find.text('Pular tudo'));
    await settle(tester);
    expect(find.text('HOJE'), findsOneWidget);
    expect((await ConfigRepository(db).load()).onboarded, isTrue);
  });

  testWidgets('PIN ligado pede o PIN ao abrir', (tester) async {
    final db = await openWidgetDb();
    final pins = MemoryPinStore();
    await PinService(pins).setPin('2468');
    await ConfigRepository(db).set(ConfigRepository.pinEnabled, '1');
    await pumpApp(tester, db, pins: pins);
    expect(find.text('Digite o seu PIN'), findsOneWidget);
    for (final d in ['1', '1', '1', '1']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel('Confirmar'));
    await settle(tester, 4);
    expect(find.text('PIN incorreto'), findsOneWidget);
    for (final d in ['2', '4', '6', '8']) {
      await tester.tap(find.text(d).last);
      await tester.pump();
    }
    await tester.tap(find.bySemanticsLabel('Confirmar'));
    await settle(tester, 4);
    expect(find.text('Digite o seu PIN'), findsNothing);
    expect(find.text('HOJE'), findsOneWidget);
  });
}
