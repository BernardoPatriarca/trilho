// Onboarding (primeira execução): boas-vindas, notificações, alarme exato,
// bateria, horário do resumo e categorias iniciais. Tudo pode ser pulado e
// refeito depois em Mais.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/utils/icons.dart';
import '../../core/widgets/form_fields.dart';
import '../../domain/dates.dart';
import 'config_repository.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key, this.fromSettings = false});

  /// Refeito a partir de Mais (ao terminar, volta em vez de ir para Hoje).
  final bool fromSettings;

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pages = PageController();
  int _index = 0;
  static const _count = 6;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    if (_index == _count - 1) {
      _finish();
      return;
    }
    _pages.nextPage(duration: shortAnimation, curve: Curves.easeOut);
  }

  Future<void> _finish() async {
    await ref.read(configRepositoryProvider).set(ConfigRepository.onboarded, '1');
    ref.dataChanged();
    if (!mounted) return;
    if (widget.fromSettings) {
      context.pop();
    } else {
      context.go('/hoje');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final local = ref.watch(localNotificationsProvider);
    final sys = ref.watch(systemSettingsProvider);
    final cfg = ref.watch(configProvider).value;
    final cats = ref.watch(categoriesProvider).value ?? const [];

    final steps = <_Step>[
      const _Step(
        icon: Icons.alt_route,
        title: 'Bem-vindo ao Trilho',
        text:
            'Agenda, calendário e tarefas num lugar só. Tudo fica no seu celular: sem conta, sem nuvem, sem internet.\n\n'
            'Toque em + em qualquer aba e escreva do seu jeito: "Mercado amanhã 18h @compras !2".',
      ),
      _Step(
        icon: Icons.notifications_active_outlined,
        title: 'Lembretes de verdade',
        text:
            'Para avisar na hora certa, mesmo com o celular bloqueado, o Trilho precisa poder mostrar notificações. '
            'Na próxima tela o Android vai perguntar: toque em "Permitir".',
        action: 'Permitir notificações',
        onAction: () async => local?.requestNotifications(),
      ),
      _Step(
        icon: Icons.alarm_on_outlined,
        title: 'Horário exato',
        text:
            'Lembretes no minuto certo usam a permissão "Alarmes e lembretes". Na maioria dos celulares ela já vem ligada; '
            'se não, o botão abre a tela do sistema. Sem ela, os lembretes podem atrasar alguns minutos.',
        action: 'Verificar alarmes',
        onAction: () async {
          final ok = await local?.canScheduleExact() ?? true;
          if (!ok) await local?.requestExactAlarms();
        },
      ),
      _Step(
        icon: Icons.battery_saver_outlined,
        title: 'Economia de bateria',
        text:
            'Alguns fabricantes (Xiaomi, Samsung, Motorola) seguram os alarmes no modo econômico. '
            'Tire o Trilho da otimização de bateria para os lembretes não falharem.',
        action: 'Desativar otimização',
        onAction: sys.requestIgnoreBatteryOptimizations,
      ),
      _Step(
        icon: Icons.wb_sunny_outlined,
        title: 'Resumo do dia',
        text: 'Toda manhã, uma notificação silenciosa com os eventos, as tarefas importantes e as atrasadas.',
        extra: Column(
          children: [
            SwitchListTile(
              title: const Text('Receber o resumo'),
              value: cfg?.summaryEnabled ?? true,
              onChanged: (v) async {
                await ref.read(configRepositoryProvider).set(ConfigRepository.summaryEnabled, v ? '1' : '0');
                ref.dataChanged();
              },
            ),
            FieldButton(
              label: 'Horário',
              icon: Icons.schedule,
              value: minutesToHm(cfg?.summaryMinutes ?? 7 * 60),
              onTap: () async {
                final m = await pickTime(context, cfg?.summaryMinutes ?? 7 * 60);
                if (m == null) return;
                await ref.read(configRepositoryProvider).set(ConfigRepository.summaryTime, minutesToHm(m));
                ref.dataChanged();
              },
            ),
          ],
        ),
      ),
      _Step(
        icon: Icons.folder_outlined,
        title: 'Suas categorias',
        text: 'Deixe ligadas as que fazem sentido para você. Dá para criar, editar e reordenar depois em Mais › Categorias.',
        extra: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final cat in cats)
              FilterChip(
                avatar: Icon(categoryIcon(cat.icon), size: 18, color: cat.active ? c.onAccent : hexColor(cat.color)),
                label: Text(cat.name),
                selected: cat.active,
                onSelected: (v) async {
                  await ref.read(categoryRepositoryProvider).setActive(cat.id!, v);
                  ref.dataChanged();
                },
              ),
          ],
        ),
      ),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _finish, child: const Text('Pular tudo')),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [for (final s in steps) _StepView(step: s)],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: Row(
                children: [
                  Semantics(
                    label: 'Passo ${_index + 1} de $_count',
                    child: Row(
                      children: [
                        for (var i = 0; i < _count; i++)
                          AnimatedContainer(
                            duration: shortAnimation,
                            width: i == _index ? 20 : 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: i == _index ? c.accent : c.surfaceHigh,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_index > 0 && _index < _count - 1) TextButton(onPressed: _next, child: const Text('Pular')),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('onboardingNext'),
                    onPressed: _next,
                    child: Text(_index == _count - 1 ? 'Começar' : 'Próximo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Step {
  const _Step({required this.icon, required this.title, required this.text, this.action, this.onAction, this.extra});
  final IconData icon;
  final String title;
  final String text;
  final String? action;
  final Future<void> Function()? onAction;
  final Widget? extra;
}

class _StepView extends StatelessWidget {
  const _StepView({required this.step});
  final _Step step;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Icon(step.icon, size: 64, color: c.accent),
          const SizedBox(height: 24),
          Text(step.title.toUpperCase(), style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(step.text, style: TextStyle(fontSize: 16, height: 1.45, color: c.textSecondary)),
          if (step.action != null) ...[
            const SizedBox(height: 24),
            OutlinedButton.icon(onPressed: step.onAction, icon: Icon(step.icon), label: Text(step.action!)),
          ],
          if (step.extra != null) ...[const SizedBox(height: 24), step.extra!],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
