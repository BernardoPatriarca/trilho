import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trilho/app/theme.dart';

import 'helpers.dart';

void main() {
  testWidgets('abre na aba Hoje com a data por extenso', (tester) async {
    await pumpApp(tester, await openWidgetDb());
    expect(find.text('HOJE'), findsOneWidget);
    expect(find.text('Terça-feira, 17 de novembro'), findsOneWidget);
  });

  testWidgets('navega pelas 5 abas e o FAB some só em Mais', (tester) async {
    await pumpApp(tester, await openWidgetDb());
    final fab = find.byKey(const Key('quickAddFab'));

    for (final (tab, title) in const [('Agenda', 'AGENDA'), ('Tarefas', 'TAREFAS'), ('Estatísticas', 'ESTATÍSTICAS')]) {
      await tester.tap(find.text(tab));
      await settle(tester);
      expect(find.text(title), findsOneWidget);
      expect(fab, findsOneWidget);
    }

    await tester.tap(find.text('Mais'));
    await settle(tester);
    expect(find.text('MAIS'), findsOneWidget);
    expect(fab, findsNothing);
  });

  testWidgets('FAB abre a adição rápida com o seletor Tarefa/Evento', (tester) async {
    await pumpApp(tester, await openWidgetDb());
    await tester.tap(find.byKey(const Key('quickAddFab')));
    await settle(tester);
    expect(find.text('ADIÇÃO RÁPIDA'), findsOneWidget);
    expect(find.byKey(const Key('quickAddField')), findsOneWidget);
    expect(find.text('Tarefa'), findsOneWidget);
    expect(find.text('Evento'), findsOneWidget);
  });

  testWidgets('trocar o tema em Mais aplica o claro', (tester) async {
    await pumpApp(tester, await openWidgetDb());
    await tester.tap(find.text('Mais'));
    await settle(tester);
    await tester.dragUntilVisible(find.text('Preferências'), find.text('Categorias'), const Offset(0, -250));
    await tester.pump();
    await tester.tap(find.text('Preferências'));
    await settle(tester);
    await tester.tap(find.text('Claro'));
    await settle(tester);
    final context = tester.element(find.text('PREFERÊNCIAS'));
    expect(Theme.of(context).brightness, Brightness.light);
    expect(context.colors.background, TrilhoColors.light.background);
  });

  testWidgets('aguenta tela de 320 dp com fonte 1,3x', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    await pumpApp(tester, await openWidgetDb());
    for (final tab in const ['Agenda', 'Tarefas', 'Estatísticas', 'Mais']) {
      await tester.tap(find.text(tab).last);
      await settle(tester);
      expect(tester.takeException(), isNull);
    }
  });
}
