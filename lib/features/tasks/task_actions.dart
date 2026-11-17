// Ações de tarefa usadas em várias telas: concluir (com desfazer), reabrir,
// adiar (atalhos da regra 4) e excluir. Usam o container do Riverpod para o
// "Desfazer" funcionar mesmo depois que o item saiu da lista.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';
import '../../domain/tasks.dart';

ProviderContainer _c(BuildContext context) => ProviderScope.containerOf(context, listen: false);

Future<void> completeTask(BuildContext context, Task t) async {
  final c = _c(context);
  final messenger = ScaffoldMessenger.of(context);
  // Vibração leve (sem esperar: não pode segurar a conclusão).
  unawaited(HapticFeedback.lightImpact());
  final repo = c.read(taskRepositoryProvider);
  final r = await repo.complete(t.id!, c.now());
  notifyDataChanged(c);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text(r.nextId != null ? 'Concluída. A próxima já foi criada.' : 'Concluída: ${t.title}'),
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () async {
          await repo.undoComplete(r);
          notifyDataChanged(c);
        },
      ),
    ),
  );
}

Future<void> reopenTask(BuildContext context, Task t) async {
  final c = _c(context);
  await c.read(taskRepositoryProvider).reopen(t.id!, c.now());
  notifyDataChanged(c);
}

Future<void> postponeTask(BuildContext context, Task t, DateTime date, int? minutes, {String? label}) async {
  final c = _c(context);
  final messenger = ScaffoldMessenger.of(context);
  final repo = c.read(taskRepositoryProvider);
  final before = await repo.postponeTo(t.id!, date, minutes, c.now());
  notifyDataChanged(c);
  final when = minutes == null ? dayMonth(date) : '${dayMonth(date)} às ${minutesToHm(minutes)}';
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Text('Adiada para $when'),
      action: SnackBarAction(
        label: 'Desfazer',
        onPressed: () async {
          await repo.restore(before);
          notifyDataChanged(c);
        },
      ),
    ),
  );
}

/// Adiar pelo padrão (`adiar_padrao_min`), usado no gesto de arrastar.
Future<void> postponeDefault(BuildContext context, Task t) async {
  final c = _c(context);
  final minutes = (await c.read(configProvider.future)).postponeMinutes;
  final at = c.now().add(Duration(minutes: minutes));
  if (!context.mounted) return;
  await postponeTask(context, t, dateOnly(at), minutesOfDay(at));
}

/// Bottom sheet com os atalhos de adiar e "Escolher data".
Future<void> showPostponeSheet(BuildContext context, Task t) async {
  final c = _c(context);
  final now = c.now();
  final minutes = (await c.read(configProvider.future)).postponeMinutes;
  if (!context.mounted) return;
  final options = postponeOptions(t, now, defaultMinutes: minutes);
  final choice = await showModalBottomSheet<Object>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: SectionTitle('Adiar')),
          for (final o in options)
            ListTile(
              leading: const Icon(Icons.schedule),
              title: Text(o.label),
              subtitle: Text(
                o.minutes == null ? dayMonth(o.date) : '${dayMonth(o.date)} às ${minutesToHm(o.minutes!)}',
              ),
              onTap: () => Navigator.pop(ctx, o),
            ),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Escolher data'),
            onTap: () => Navigator.pop(ctx, 'escolher'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || choice == null) return;
  if (choice is PostponeOption) {
    await postponeTask(context, t, choice.date, choice.minutes);
    return;
  }
  final date = await showDatePicker(
    context: context,
    initialDate: addDays(dateOnly(now), 1),
    firstDate: DateTime(now.year - 1),
    lastDate: DateTime(now.year + 5),
  );
  if (date == null || !context.mounted) return;
  int? m = t.dueMinutes;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: (m ?? 9 * 60) ~/ 60, minute: (m ?? 0) % 60),
    helpText: 'Hora (opcional: cancele para só a data)',
  );
  m = time == null ? null : time.hour * 60 + time.minute;
  if (!context.mounted) return;
  await postponeTask(context, t, date, m);
}

Future<bool> deleteTask(BuildContext context, Task t) async {
  final ok = await confirm(
    context,
    title: 'Excluir tarefa?',
    message: '"${t.title}" será apagada com a checklist e os lembretes.',
    confirmLabel: 'Excluir',
    destructive: true,
  );
  if (!ok || !context.mounted) return false;
  final c = _c(context);
  await c.read(taskRepositoryProvider).delete(t.id!);
  notifyDataChanged(c);
  return true;
}
