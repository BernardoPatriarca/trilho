// Raiz do app: temas, locale pt_BR, rotas, onboarding na primeira execução,
// PIN opcional, toque em notificação abrindo o item e reagendamento ao abrir
// e ao voltar para o app.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import '../features/settings/settings_pages.dart';
import 'router.dart';
import 'theme.dart';

/// Rota pedida por um toque em notificação (main.dart preenche).
final pendingRoute = ValueNotifier<String?>(null);

/// Quanto tempo em segundo plano até pedir o PIN de novo.
const _relockAfter = Duration(minutes: 2);

class TrilhoApp extends ConsumerStatefulWidget {
  const TrilhoApp({super.key});

  @override
  ConsumerState<TrilhoApp> createState() => _TrilhoAppState();
}

class _TrilhoAppState extends ConsumerState<TrilhoApp> {
  late final GoRouter _router = buildRouter();
  late final AppLifecycleListener _lifecycle;
  bool _unlocked = false;
  bool _checkedOnboarding = false;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () => _hiddenAt = DateTime.now(),
      onShow: () {
        // Pode ter virado o dia: atualiza as telas e reagenda (janela rolante).
        ref.dataChanged();
        final hidden = _hiddenAt;
        if (hidden != null && DateTime.now().difference(hidden) > _relockAfter && mounted) {
          setState(() => _unlocked = false);
        }
      },
    );
    pendingRoute.addListener(_openPending);
    // Ao abrir: reagenda tudo (idempotente).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(ref.resync());
      _openPending();
    });
  }

  void _openPending() {
    final r = pendingRoute.value;
    if (r == null) return;
    pendingRoute.value = null;
    if (r == '/hoje') {
      _router.go(r);
    } else {
      _router.push(r);
    }
  }

  @override
  void dispose() {
    pendingRoute.removeListener(_openPending);
    _lifecycle.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfg = ref.watch(configProvider).value;
    if (cfg != null && !_checkedOnboarding) {
      _checkedOnboarding = true;
      if (!cfg.onboarded) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _router.go('/onboarding'));
      }
    }
    final locked = (cfg?.pinEnabled ?? false) && !_unlocked;
    return MaterialApp.router(
      title: 'Trilho',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      themeAnimationDuration: shortAnimation,
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: _router,
      builder: (context, child) {
        if (!locked) return child!;
        return Stack(
          children: [
            child!,
            Positioned.fill(child: LockScreen(onUnlocked: () => setState(() => _unlocked = true))),
          ],
        );
      },
    );
  }
}
