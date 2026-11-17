// Raiz do app: temas claro e escuro, locale pt_BR e rotas.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../core/providers.dart';
import 'router.dart';
import 'theme.dart';

class TrilhoApp extends ConsumerStatefulWidget {
  const TrilhoApp({super.key});

  @override
  ConsumerState<TrilhoApp> createState() => _TrilhoAppState();
}

class _TrilhoAppState extends ConsumerState<TrilhoApp> {
  late final GoRouter _router = buildRouter();

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
    );
  }
}
