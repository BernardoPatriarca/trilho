// Mais › Backup e exportação: backup JSON (compartilhar), importar
// (substitui tudo, confirmação dupla, reagenda), eventos em .ics e lembrete
// semanal de backup.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../domain/dates.dart';
import '../../domain/ics.dart';
import 'backup_service.dart';
import 'config_repository.dart';

Future<void> _shareFile(String name, String content, String mime) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsString(content);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: mime, name: name)],
      subject: name,
    ),
  );
}

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});

  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _busy = true);
    try {
      await f();
    } on BackupException catch (e) {
      if (mounted) showSnack(context, e.message);
    } on Object catch (e) {
      if (mounted) showSnack(context, 'Não deu certo: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() => _run(() async {
    final now = ref.now();
    final json = await ref.read(backupServiceProvider).exportJson(now: now);
    await _shareFile(BackupService.fileName(now), json, 'application/json');
    await ref.read(configRepositoryProvider).set(ConfigRepository.lastBackup, now.toIso8601String());
    ref.dataChanged();
  });

  Future<void> _import() => _run(() async {
    final picked = await FilePicker.pickFile(type: FileType.any);
    if (picked == null) return;
    final path = picked.path;
    if (path == null) throw BackupException('Não consegui ler o arquivo escolhido.');
    final service = ref.read(backupServiceProvider);
    final data = service.decode(await File(path).readAsString());
    final s = service.validate(data);
    if (!mounted) return;
    final when = s.exportedAt == null ? '' : ' de ${dayMonthYear(s.exportedAt!)}';
    final ok1 = await confirm(
      context,
      title: 'Importar backup$when?',
      message: '${s.tasks} tarefas e ${s.events} eventos. Isto SUBSTITUI todos os dados atuais do Trilho.',
      confirmLabel: 'Continuar',
    );
    if (!ok1 || !mounted) return;
    final ok2 = await confirm(
      context,
      title: 'Tem certeza?',
      message: 'Os dados de agora serão apagados e não dá para desfazer.',
      confirmLabel: 'Substituir tudo',
      destructive: true,
    );
    if (!ok2) return;
    await service.importData(data);
    await ref.read(schedulerProvider).rescheduleAll();
    ref.read(dataRevisionProvider.notifier).bump();
    if (mounted) showSnack(context, 'Backup importado e notificações reagendadas');
  });

  Future<void> _exportIcs() => _run(() async {
    final now = ref.now();
    final series = await ref.read(eventRepositoryProvider).allSeries();
    if (series.isEmpty) throw BackupException('Nenhum evento para exportar.');
    final cats = ref.read(categoryMapProvider);
    final ics = exportIcs(series, now: now, categoryNames: {for (final c in cats.values) c.id!: c.name});
    await _shareFile('trilho-eventos-${toIsoDate(now)}.ics', ics, 'text/calendar');
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cfg = ref.watch(configProvider).value;
    final last = cfg?.lastBackup;
    return Scaffold(
      appBar: AppBar(title: const Text('BACKUP E EXPORTAÇÃO')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            if (_busy) const LinearProgressIndicator(),
            AppCard(
              child: Row(
                children: [
                  Icon(
                    last == null ? Icons.warning_amber_rounded : Icons.verified_outlined,
                    color: last == null ? c.warning : c.success,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      last == null
                          ? 'Você ainda não fez nenhum backup.'
                          : 'Último backup: ${dayMonthYear(last)} às ${hm(last)}',
                    ),
                  ),
                ],
              ),
            ),
            const SectionTitle('Backup'),
            FilledButton.icon(
              onPressed: _export,
              icon: const Icon(Icons.upload_file),
              label: const Text('Exportar backup (.json)'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download),
              label: const Text('Importar backup'),
            ),
            const SizedBox(height: 6),
            Text(
              'O arquivo traz todas as tabelas e a versão do banco. Importar substitui tudo.',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            const SectionTitle('Outros calendários'),
            OutlinedButton.icon(
              onPressed: _exportIcs,
              icon: const Icon(Icons.calendar_month),
              label: const Text('Exportar eventos (.ics)'),
            ),
            const SizedBox(height: 6),
            Text(
              'Formato iCalendar, com as repetições (RRULE). Abre no Google Agenda ou em outro app de calendário.',
              style: TextStyle(fontSize: 12, color: c.textSecondary),
            ),
            const SectionTitle('Lembrete'),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                title: const Text('Lembrar de fazer backup toda semana'),
                subtitle: const Text('Uma notificação no domingo às 20h'),
                value: cfg?.weeklyBackupReminder ?? false,
                onChanged: (v) async {
                  await ref.read(configRepositoryProvider).set(ConfigRepository.weeklyBackup, v ? '1' : '0');
                  ref.dataChanged();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
