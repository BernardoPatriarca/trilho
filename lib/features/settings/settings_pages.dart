// Mais › Preferências (início da semana, lembretes padrão, adiar, tema),
// PIN opcional e Sobre.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/form_fields.dart';
import '../../domain/dates.dart';
import 'config_repository.dart';
import 'pin_service.dart';

class PreferencesPage extends ConsumerWidget {
  const PreferencesPage({super.key});

  Future<void> _set(WidgetRef ref, String key, String value) async {
    await ref.read(configRepositoryProvider).set(key, value);
    ref.dataChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = ref.watch(configProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('PREFERÊNCIAS')),
      body: AsyncView(
        cfg,
        builder: (cfg) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              const SectionTitle('Tema'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'sistema', label: Text('Sistema')),
                    ButtonSegment(value: 'escuro', label: Text('Escuro')),
                    ButtonSegment(value: 'claro', label: Text('Claro')),
                  ],
                  selected: {cfg.theme},
                  onSelectionChanged: (s) => _set(ref, ConfigRepository.theme, s.first),
                ),
              ),
              const SectionTitle('Início da semana'),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: true, label: Text('Segunda')),
                    ButtonSegment(value: false, label: Text('Domingo')),
                  ],
                  selected: {cfg.mondayFirst},
                  onSelectionChanged: (s) => _set(ref, ConfigRepository.weekStart, s.first ? 'segunda' : 'domingo'),
                ),
              ),
              const SectionTitle('Lembretes padrão'),
              _Stepper(
                label: 'Eventos: avisar antes do início',
                value: cfg.defaultEventReminder,
                options: const [0, 5, 10, 15, 30, 60, 120],
                format: (m) => m == 0 ? 'Na hora' : (m % 60 == 0 ? '${m ~/ 60} h' : '$m min'),
                onChanged: (v) => _set(ref, ConfigRepository.defaultEventReminder, '$v'),
              ),
              const SizedBox(height: 8),
              FieldButton(
                label: 'Tarefas só com data: lembrar às',
                icon: Icons.schedule,
                value: minutesToHm(cfg.defaultTaskMinutes),
                onTap: () async {
                  final m = await pickTime(context, cfg.defaultTaskMinutes);
                  if (m != null) await _set(ref, ConfigRepository.defaultTaskTime, minutesToHm(m));
                },
              ),
              const SectionTitle('Adiar'),
              _Stepper(
                label: 'Arrastar para a esquerda adia',
                value: cfg.postponeMinutes,
                options: const [15, 30, 60, 120, 180],
                format: (m) => m % 60 == 0 ? '${m ~/ 60} h' : '$m min',
                onChanged: (v) => _set(ref, ConfigRepository.postponeDefault, '$v'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.options,
    required this.format,
    required this.onChanged,
  });
  final String label;
  final int value;
  final List<int> options;
  final String Function(int) format;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: context.colors.textSecondary)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in options)
              ChoiceChip(label: Text(format(o)), selected: value == o, onSelected: (_) => onChanged(o)),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- PIN

final pinServiceProvider = Provider((ref) => PinService(ref.watch(pinStoreProvider)));

/// Teclado de PIN (4 a 8 dígitos). Usado no bloqueio e na configuração.
class PinPad extends StatefulWidget {
  const PinPad({super.key, required this.title, required this.onSubmit, this.subtitle, this.error});
  final String title;
  final String? subtitle;
  final String? error;
  final Future<void> Function(String pin) onSubmit;

  @override
  State<PinPad> createState() => _PinPadState();
}

class _PinPadState extends State<PinPad> {
  String _pin = '';

  void _tap(String d) {
    if (_pin.length >= 8) return;
    setState(() => _pin += d);
  }

  Future<void> _ok() async {
    if (_pin.length < 4) return;
    final p = _pin;
    setState(() => _pin = '');
    await widget.onSubmit(p);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget key(String label, {VoidCallback? onTap, IconData? icon, String? semantics}) => Padding(
      padding: const EdgeInsets.all(6),
      child: Semantics(
        button: true,
        label: semantics ?? label,
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap ?? () => _tap(label),
            child: SizedBox(
              width: 72,
              height: 72,
              child: Center(child: icon != null ? Icon(icon) : Text(label, style: numberStyle(context, 26))),
            ),
          ),
        ),
      ),
    );
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: c.accent),
              const SizedBox(height: 12),
              Text(widget.title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.subtitle!,
                    style: TextStyle(color: c.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              const SizedBox(height: 16),
              Semantics(
                label: '${_pin.length} dígitos digitados',
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < (_pin.length < 4 ? 4 : _pin.length); i++)
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i < _pin.length ? c.accent : Colors.transparent,
                          border: Border.all(color: c.accent, width: 2),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(
                height: 24,
                child: widget.error == null ? null : Text(widget.error!, style: TextStyle(color: c.error)),
              ),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
              ])
                Row(mainAxisSize: MainAxisSize.min, children: [for (final d in row) key(d)]),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  key(
                    'apagar',
                    icon: Icons.backspace_outlined,
                    semantics: 'Apagar',
                    onTap: () {
                      if (_pin.isNotEmpty) setState(() => _pin = _pin.substring(0, _pin.length - 1));
                    },
                  ),
                  key('0'),
                  key('ok', icon: Icons.check, semantics: 'Confirmar', onTap: _ok),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tela de bloqueio na abertura (quando o PIN está ligado).
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key, required this.onUnlocked});
  final VoidCallback onUnlocked;

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _error;
  int _attempts = 0;
  DateTime? _blockedUntil;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PinPad(
        title: 'TRILHO',
        subtitle: 'Digite o seu PIN',
        error: _error,
        onSubmit: (pin) async {
          final now = DateTime.now();
          if (_blockedUntil != null && now.isBefore(_blockedUntil!)) {
            setState(() => _error = 'Aguarde ${_blockedUntil!.difference(now).inSeconds + 1} s');
            return;
          }
          if (await ref.read(pinServiceProvider).check(pin)) {
            widget.onUnlocked();
            return;
          }
          _attempts++;
          if (_attempts >= 5) {
            _attempts = 0;
            _blockedUntil = now.add(const Duration(seconds: 30));
          }
          setState(
            () => _error = _blockedUntil != null && now.isBefore(_blockedUntil!)
                ? 'Muitas tentativas. Aguarde 30 s.'
                : 'PIN incorreto',
          );
        },
      ),
    );
  }
}

class PinSettingsPage extends ConsumerStatefulWidget {
  const PinSettingsPage({super.key});

  @override
  ConsumerState<PinSettingsPage> createState() => _PinSettingsPageState();
}

class _PinSettingsPageState extends ConsumerState<PinSettingsPage> {
  String? _first;
  String? _error;
  bool _creating = false;

  Future<void> _disable() async {
    await ref.read(pinServiceProvider).clear();
    await ref.read(configRepositoryProvider).set(ConfigRepository.pinEnabled, '0');
    ref.dataChanged();
    if (mounted) showSnack(context, 'PIN desligado');
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider).value;
    if (_creating) {
      return Scaffold(
        appBar: AppBar(title: const Text('PIN')),
        body: PinPad(
          title: _first == null ? 'Escolha um PIN' : 'Repita o PIN',
          subtitle: 'De 4 a 8 números',
          error: _error,
          onSubmit: (pin) async {
            final err = PinService.validate(pin);
            if (err != null) {
              setState(() => _error = err);
              return;
            }
            if (_first == null) {
              setState(() {
                _first = pin;
                _error = null;
              });
              return;
            }
            if (_first != pin) {
              setState(() {
                _first = null;
                _error = 'Os PINs não batem. Comece de novo.';
              });
              return;
            }
            await ref.read(pinServiceProvider).setPin(pin);
            await ref.read(configRepositoryProvider).set(ConfigRepository.pinEnabled, '1');
            ref.dataChanged();
            if (!context.mounted) return;
            setState(() {
              _creating = false;
              _first = null;
            });
            showSnack(context, 'PIN ligado. Ele será pedido ao abrir o app.');
          },
        ),
      );
    }
    final on = cfg?.pinEnabled ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('PIN')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              title: const Text('Pedir PIN ao abrir'),
              subtitle: const Text('Guardado como hash SHA-256 com salt no armazenamento seguro do Android'),
              value: on,
              onChanged: (v) => v ? setState(() => _creating = true) : _disable(),
            ),
          ),
          if (on) ...[
            const SizedBox(height: 12),
            OutlinedButton(onPressed: () => setState(() => _creating = true), child: const Text('Trocar PIN')),
          ],
          const SizedBox(height: 12),
          Text(
            'Esqueceu o PIN? Sem ele, só reinstalando o app (e importando um backup).',
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ Sobre

class AboutPage extends ConsumerWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('SOBRE')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          Center(
            child: Image.asset('assets/branding/icon.png', width: 96, height: 96, semanticLabel: 'Ícone do Trilho'),
          ),
          const SizedBox(height: 12),
          Center(child: Text('TRILHO', style: Theme.of(context).textTheme.headlineMedium)),
          Center(
            child: Text('Versão 1.0.1', style: TextStyle(color: c.textSecondary)),
          ),
          const SizedBox(height: 16),
          const Text(
            'O caminho que mantém o seu dia no curso. Agenda, calendário e tarefas num lugar só, '
            'da mesma família do Lastro (finanças) e do Fôlego (treino).',
          ),
          const SizedBox(height: 12),
          const Text(
            '100% offline: sem conta, sem nuvem, sem analytics e sem permissão de internet. '
            'Seus dados só saem do celular pelo backup que você exporta.',
          ),
          const SizedBox(height: 12),
          Text(
            'Fontes Oswald e Rubik (SIL Open Font License).',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
          if (kDebugMode) ...[
            const SectionTitle('Debug'),
            OutlinedButton(
              onPressed: () async {
                final sw = Stopwatch()..start();
                await ref.read(eventRepositoryProvider).seedLoad(2000, ref.now());
                ref.dataChanged();
                if (context.mounted) {
                  showSnack(context, '2.000 eventos de carga criados em ${sw.elapsedMilliseconds} ms');
                }
              },
              child: const Text('Gerar 2.000 eventos de carga'),
            ),
          ],
        ],
      ),
    );
  }
}
