// Tema do Trilho: painel sóbrio, azul-lavanda sobre grafite (escuro, padrão)
// ou sobre papel (claro). As cores ficam numa ThemeExtension para as telas
// lerem `context.colors` e funcionarem nos dois temas.
import 'package:material_ui/material_ui.dart';

import '../domain/priority.dart';

/// Paleta de um dos temas. Use `context.colors` nas telas.
@immutable
class TrilhoColors extends ThemeExtension<TrilhoColors> {
  const TrilhoColors({
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.border,
    required this.text,
    required this.textSecondary,
    required this.accent,
    required this.onAccent,
    required this.error,
    required this.warning,
    required this.success,
  });

  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color border;
  final Color text;
  final Color textSecondary;

  /// Destaque do Trilho (azul-lavanda).
  final Color accent;

  /// Texto sobre o destaque: sempre escuro.
  final Color onAccent;
  final Color error;
  final Color warning;
  final Color success;

  static const dark = TrilhoColors(
    background: Color(0xFF12161C),
    surface: Color(0xFF1D242E),
    surfaceHigh: Color(0xFF2A333F),
    border: Color(0xFF323C49),
    text: Color(0xFFF3F1EA),
    textSecondary: Color(0xFFA9B3BF),
    accent: Color(0xFF8FA8FF),
    onAccent: Color(0xFF12161C),
    error: Color(0xFFFF6B6B),
    warning: Color(0xFFFFB259),
    success: Color(0xFF5FD39A),
  );

  // No claro, erro/aviso/sucesso usam tons mais escuros só para manter o
  // contraste de texto sobre o fundo creme (mesma ideia do Lastro).
  static const light = TrilhoColors(
    background: Color(0xFFF3F1EA),
    surface: Color(0xFFE6E2D6),
    surfaceHigh: Color(0xFFD9D4C5),
    border: Color(0xFFC9C3B2),
    text: Color(0xFF12161C),
    textSecondary: Color(0xFF4A5260),
    accent: Color(0xFF8FA8FF),
    onAccent: Color(0xFF12161C),
    error: Color(0xFFC62828),
    warning: Color(0xFFB45309),
    success: Color(0xFF1B7F4B),
  );

  @override
  TrilhoColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceHigh,
    Color? border,
    Color? text,
    Color? textSecondary,
    Color? accent,
    Color? onAccent,
    Color? error,
    Color? warning,
    Color? success,
  }) => TrilhoColors(
    background: background ?? this.background,
    surface: surface ?? this.surface,
    surfaceHigh: surfaceHigh ?? this.surfaceHigh,
    border: border ?? this.border,
    text: text ?? this.text,
    textSecondary: textSecondary ?? this.textSecondary,
    accent: accent ?? this.accent,
    onAccent: onAccent ?? this.onAccent,
    error: error ?? this.error,
    warning: warning ?? this.warning,
    success: success ?? this.success,
  );

  @override
  TrilhoColors lerp(TrilhoColors? other, double t) {
    if (other == null) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return TrilhoColors(
      background: l(background, other.background),
      surface: l(surface, other.surface),
      surfaceHigh: l(surfaceHigh, other.surfaceHigh),
      border: l(border, other.border),
      text: l(text, other.text),
      textSecondary: l(textSecondary, other.textSecondary),
      accent: l(accent, other.accent),
      onAccent: l(onAccent, other.onAccent),
      error: l(error, other.error),
      warning: l(warning, other.warning),
      success: l(success, other.success),
    );
  }
}

extension TrilhoThemeContext on BuildContext {
  TrilhoColors get colors => Theme.of(this).extension<TrilhoColors>() ?? TrilhoColors.dark;
}

/// Cores das prioridades (iguais nos dois temas). Sempre exibidas com rótulo.
Color priorityColor(Priority p) => switch (p) {
  Priority.p1 => const Color(0xFFFF5A5F),
  Priority.p2 => const Color(0xFFFF9F43),
  Priority.p3 => const Color(0xFF4DA3FF),
  Priority.p4 => const Color(0xFF8A94A3),
};

const headingFont = 'Oswald';
const bodyFont = 'Rubik';
const tabular = [FontFeature.tabularFigures()];

/// Duração padrão das animações (a especificação pede até 250 ms).
const shortAnimation = Duration(milliseconds: 200);

/// Estilo para números grandes (Oswald, algarismos tabulares).
TextStyle numberStyle(BuildContext context, double size, {Color? color, FontWeight weight = FontWeight.w600}) =>
    TextStyle(
      fontFamily: headingFont,
      fontSize: size,
      fontWeight: weight,
      color: color ?? context.colors.text,
      fontFeatures: tabular,
      height: 1.1,
    );

ThemeData buildTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? TrilhoColors.dark : TrilhoColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: c.accent,
    onPrimary: c.onAccent,
    secondary: c.accent,
    onSecondary: c.onAccent,
    tertiary: c.warning,
    onTertiary: c.onAccent,
    error: c.error,
    onError: brightness == Brightness.dark ? c.onAccent : Colors.white,
    surface: c.background,
    onSurface: c.text,
    onSurfaceVariant: c.textSecondary,
    surfaceContainerLowest: c.background,
    surfaceContainerLow: c.surface,
    surfaceContainer: c.surface,
    surfaceContainerHigh: c.surfaceHigh,
    surfaceContainerHighest: c.surfaceHigh,
    outline: c.border,
    outlineVariant: c.border,
    primaryContainer: c.surfaceHigh,
    onPrimaryContainer: c.text,
    secondaryContainer: c.accent,
    onSecondaryContainer: c.onAccent,
    inverseSurface: c.text,
    onInverseSurface: c.background,
  );

  TextStyle h(double size, [FontWeight w = FontWeight.w600]) => TextStyle(
    fontFamily: headingFont,
    fontSize: size,
    fontWeight: w,
    color: c.text,
    letterSpacing: 0.4,
    fontFeatures: tabular,
  );
  TextStyle b(double size, [FontWeight w = FontWeight.w400, Color? color]) =>
      TextStyle(fontFamily: bodyFont, fontSize: size, fontWeight: w, color: color ?? c.text);

  final textTheme = TextTheme(
    displayLarge: h(56),
    displayMedium: h(44),
    displaySmall: h(36),
    headlineLarge: h(32),
    headlineMedium: h(28),
    headlineSmall: h(24),
    titleLarge: h(22, FontWeight.w500),
    titleMedium: b(16, FontWeight.w500),
    titleSmall: b(14, FontWeight.w500),
    bodyLarge: b(16),
    bodyMedium: b(14),
    bodySmall: b(12, FontWeight.w400, c.textSecondary),
    labelLarge: b(14, FontWeight.w600),
    labelMedium: b(12, FontWeight.w500),
    labelSmall: b(11, FontWeight.w500, c.textSecondary),
  );

  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(16),
    borderSide: BorderSide(color: color, width: width),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    extensions: [c],
    scaffoldBackgroundColor: c.background,
    fontFamily: bodyFont,
    textTheme: textTheme,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    appBarTheme: AppBarTheme(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: c.text,
      centerTitle: false,
      titleTextStyle: h(22, FontWeight.w500),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.border),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.accent,
      height: 68,
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(color: s.contains(WidgetState.selected) ? c.onAccent : c.textSecondary),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => b(12, FontWeight.w500, s.contains(WidgetState.selected) ? c.text : c.textSecondary),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        disabledBackgroundColor: c.surfaceHigh,
        minimumSize: const Size(48, 52),
        shape: shape,
        textStyle: b(16, FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.text,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: c.border),
        shape: shape,
        textStyle: b(14, FontWeight.w500),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        // No claro, o lavanda sobre creme tem pouco contraste: texto escuro.
        foregroundColor: brightness == Brightness.dark ? c.accent : const Color(0xFF3A4FB0),
        minimumSize: const Size(48, 48),
        textStyle: b(14, FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(minimumSize: const Size(48, 48))),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.accent,
      disabledColor: c.surface,
      labelStyle: b(14, FontWeight.w500),
      secondaryLabelStyle: b(14, FontWeight.w600, c.onAccent),
      checkmarkColor: c.onAccent,
      side: BorderSide(color: c.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      labelStyle: b(14, FontWeight.w400, c.textSecondary),
      hintStyle: b(14, FontWeight.w400, c.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: border(c.border),
      enabledBorder: border(c.border),
      focusedBorder: border(c.accent, 2),
      errorBorder: border(c.error),
      focusedErrorBorder: border(c.error, 2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: c.surfaceHigh,
      contentTextStyle: b(14),
      actionTextColor: brightness == Brightness.dark ? c.accent : const Color(0xFF3A4FB0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: h(22, FontWeight.w500),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dividerTheme: DividerThemeData(color: c.border, space: 1),
    listTileTheme: ListTileThemeData(
      iconColor: c.textSecondary,
      titleTextStyle: b(16, FontWeight.w500),
      subtitleTextStyle: b(13, FontWeight.w400, c.textSecondary),
      minVerticalPadding: 12,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
      linearTrackColor: c.surfaceHigh,
      circularTrackColor: c.surfaceHigh,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.accent : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(c.onAccent),
      side: BorderSide(color: c.textSecondary, width: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.onAccent : c.textSecondary,
      ),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceHigh),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: c.accent,
        selectedForegroundColor: c.onAccent,
        foregroundColor: c.text,
        side: BorderSide(color: c.border),
        minimumSize: const Size(48, 48),
      ),
    ),
    datePickerTheme: DatePickerThemeData(backgroundColor: c.surface, surfaceTintColor: Colors.transparent),
    timePickerTheme: TimePickerThemeData(backgroundColor: c.surface),
  );
}
