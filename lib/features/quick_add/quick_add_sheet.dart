// Adição rápida: bottom sheet aberto pelo FAB. Nesta fase já tem o campo e o
// seletor Tarefa/Evento; o parser em linguagem natural (regra 6.7) e a
// gravação entram nas fases 3, 4 e 7.
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';

enum QuickAddKind { task, event }

Future<void> showQuickAddSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const QuickAddSheet(),
  );
}

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key});

  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final _text = TextEditingController();
  QuickAddKind _kind = QuickAddKind.task;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('ADIÇÃO RÁPIDA', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            key: const Key('quickAddField'),
            controller: _text,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Mercado amanhã 18h #casa !2 @compras',
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<QuickAddKind>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: QuickAddKind.task,
                  icon: Icon(Icons.check_circle_outline),
                  label: Text('Tarefa')),
              ButtonSegment(
                  value: QuickAddKind.event,
                  icon: Icon(Icons.event_outlined),
                  label: Text('Evento')),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          Text(
            'Salvar pela adição rápida fica disponível junto com as tarefas.',
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 12),
          const FilledButton(onPressed: null, child: Text('Adicionar')),
        ],
      ),
    );
  }
}
