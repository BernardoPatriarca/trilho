// Providers de infraestrutura do app.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Relógio do app (sobrescrito nos testes para fixar "agora").
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Tema escolhido: segue o sistema por padrão (config `tema` = `sistema`).
/// A partir da fase do banco ele passa a ser lido e gravado na tabela config.
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
