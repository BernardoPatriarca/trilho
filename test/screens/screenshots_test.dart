// Gera capturas das telas principais (não roda no CI: só com
// `flutter test test/screens --dart-define=SCREENSHOTS=1`).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/features/events/event_repository.dart';
import 'package:trilho/features/settings/config_repository.dart';
import 'package:trilho/features/tasks/task_repository.dart';

import '../widget/helpers.dart';

const _enabled = bool.fromEnvironment('SCREENSHOTS');

Future<void> _loadFonts() async {
  for (final (family, files) in [
    ('Oswald', ['Regular', 'Medium', 'SemiBold', 'Bold']),
    ('Rubik', ['Regular', 'Medium', 'SemiBold', 'Bold']),
  ]) {
    final loader = FontLoader(family);
    for (final f in files) {
      loader.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$family-$f.ttf').readAsBytesSync())));
    }
    await loader.load();
  }
  final mi = FontLoader('MaterialIcons');
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  mi.addFont(
    Future.value(
      ByteData.sublistView(
        File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync(),
      ),
    ),
  );
  await mi.load();
}

void main() {
  testWidgets('capturas', (tester) async {
    if (!_enabled) return;
    await _loadFonts();
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final out = Directory(const String.fromEnvironment('OUT', defaultValue: 'build/screens'))
      ..createSync(recursive: true);

    final db = await openWidgetDb();
    final now = fixedNow;
    Task t(
      String title, {
      DateTime? due,
      int? min,
      int p = 4,
      int? cat,
      TaskStatus st = TaskStatus.pendente,
      DateTime? done,
    }) => Task(
      title: title,
      dueDate: due,
      dueMinutes: min,
      priority: p,
      categoryId: cat,
      status: st,
      completedAt: done,
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now,
    );
    final tasks = TaskRepository(db);
    final market = await tasks.save(
      TaskDraft(
        task: t('Ir ao mercado', due: DateTime(2026, 11, 17), p: 2, cat: 7),
        checklist: const [
          ChecklistItem(text: 'arroz', quantity: '5 kg', checked: true),
          ChecklistItem(text: 'feijão', quantity: '1 kg', checked: true),
          ChecklistItem(text: 'óleo', quantity: '2 un'),
          ChecklistItem(text: 'açúcar'),
          ChecklistItem(text: 'café'),
          ChecklistItem(text: 'leite', quantity: '6 un'),
        ],
        tagNames: const ['casa'],
        rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [2]),
      ),
      now: now,
    );
    await tasks.save(
      TaskDraft(
        task: t('Entregar relatório do TCC', due: DateTime(2026, 11, 17), min: 16 * 60, p: 1, cat: 2),
      ),
      now: now,
    );
    await tasks.save(
      TaskDraft(task: t('Prender o varão na parede', due: DateTime(2026, 11, 15), p: 3, cat: 3)),
      now: now,
    );
    await tasks.save(
      TaskDraft(task: t('Pagar a fatura do cartão', due: DateTime(2026, 11, 17), p: 2, cat: 6)),
      now: now,
    );
    await tasks.save(
      TaskDraft(
        task: t('Ligar para o dentista', st: TaskStatus.concluida, done: DateTime(2026, 11, 17, 8, 40), cat: 5),
      ),
      now: now,
    );
    for (var i = 1; i <= 12; i++) {
      await tasks.save(
        TaskDraft(
          task: t(
            'Tarefa antiga $i',
            cat: 1 + i % 7,
            st: TaskStatus.concluida,
            done: DateTime(2026, 11, 17 - i % 7, 8 + i % 10),
          ),
        ),
        now: now,
      );
    }
    final events = EventRepository(db);
    Future<void> ev(
      String title,
      DateTime s,
      DateTime e, {
      int? cat,
      RecurrenceRule? rule,
      String? loc,
      bool allDay = false,
    }) => events.save(
      EventDraft(
        event: Event(
          title: title,
          start: s,
          end: e,
          categoryId: cat,
          location: loc,
          allDay: allDay,
          createdAt: now,
          updatedAt: now,
        ),
        rule: rule,
      ),
      now: now,
    );
    await ev(
      'Reunião de alinhamento',
      DateTime(2026, 11, 17, 9),
      DateTime(2026, 11, 17, 10),
      cat: 1,
      rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [2]),
      loc: 'Sala 3',
    );
    await ev(
      'Dentista',
      DateTime(2026, 11, 17, 14, 30),
      DateTime(2026, 11, 17, 15, 30),
      cat: 5,
      loc: 'Clínica Sorriso',
    );
    await ev(
      'Aula de inglês',
      DateTime(2026, 11, 2, 19),
      DateTime(2026, 11, 2, 20, 30),
      cat: 2,
      rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [1, 3]),
    );
    await ev(
      'Academia',
      DateTime(2026, 11, 3, 7),
      DateTime(2026, 11, 3, 8),
      cat: 4,
      rule: const RecurrenceRule(freq: Freq.semanal, weekdays: [2, 4, 6]),
    );
    await ev('Aniversário da Ana', DateTime(2026, 11, 21), DateTime(2026, 11, 21), cat: 4, allDay: true);
    await ev('Almoço com a família', DateTime(2026, 11, 22, 12), DateTime(2026, 11, 22, 14), cat: 4);
    await ConfigRepository(db).set('tema', const String.fromEnvironment('TEMA', defaultValue: 'escuro'));

    await pumpApp(tester, db);
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));

    Future<void> shot(String name) async {
      await settle(tester, 8);
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
      final image = await tester.runAsync(() => boundary.toImage(pixelRatio: 1));
      final bytes = await tester.runAsync(() => image!.toByteData(format: ui.ImageByteFormat.png));
      File('${out.path}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    }

    await shot('1-hoje');
    await tester.tap(find.text('Agenda').last);
    await shot('2-agenda-mes');
    await tester.tap(find.text('Semana').last);
    await shot('3-agenda-semana');
    await tester.tap(find.text('Dia').last);
    await shot('4-agenda-dia');
    await tester.tap(find.text('Tarefas').last);
    await shot('5-tarefas');
    await tester.tap(find.text('Estatísticas').last);
    await shot('6-estatisticas');
    router.push('/tarefa/$market');
    await settle(tester);
    await tester.scrollUntilVisible(find.text('CHECKLIST'), 300, scrollable: find.byType(Scrollable).last);
    await shot('7-tarefa-checklist');
  });
}
