// Widgets reutilizados por várias telas.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../domain/models.dart';
import '../../domain/priority.dart';
import '../../domain/text.dart';
import '../utils/icons.dart';

/// Título de seção em Oswald caixa-alta.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                text.toUpperCase(),
                style: TextStyle(
                  fontFamily: headingFont,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                  color: context.colors.textSecondary,
                ),
              ),
            ),
          ),
          if (trailing != null)
            Flexible(
              child: Align(alignment: Alignment.centerRight, child: trailing),
            ),
        ],
      ),
    );
  }
}

/// Cartão padrão (superfície com borda e cantos de 20 px).
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.onTap, this.color});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: color,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Estado vazio amigável: ícone, título e uma dica do que fazer.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action});

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: c.accent),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, height: 1.4),
              ),
            ],
            if (action != null) ...[const SizedBox(height: 20), action!],
          ],
        ),
      ),
    );
  }
}

/// Selo de prioridade: cor + rótulo ("P1 · Urgente"), nunca só a cor.
class PriorityBadge extends StatelessWidget {
  const PriorityBadge(this.priority, {super.key, this.compact = false});
  final Priority priority;

  /// Só "P1" (a cor continua acompanhada do código).
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = priorityColor(priority);
    final label = compact ? priority.code : '${priority.code} · ${priority.label}';
    return Semantics(
      label: 'Prioridade ${priority.label}',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: context.colors.text,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            fontFeatures: tabular,
          ),
        ),
      ),
    );
  }
}

/// Selo de categoria: bolinha colorida + ícone + nome (nunca só a cor).
class CategoryBadge extends StatelessWidget {
  const CategoryBadge(this.category, {super.key, this.dense = false});
  final Category category;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final color = hexColor(category.color);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(categoryIcon(category.icon), size: dense ? 14 : 16, color: color),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            category.name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: dense ? 12 : 13, color: context.colors.textSecondary),
          ),
        ),
      ],
    );
  }
}

/// Barra fina colorida da categoria (lateral dos cartões da agenda).
class CategoryStripe extends StatelessWidget {
  const CategoryStripe({super.key, required this.color, this.height = 36});
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: height,
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
  );
}

/// Anel de progresso com texto no meio.
class ProgressRing extends StatelessWidget {
  const ProgressRing({super.key, required this.value, this.size = 64, this.label, this.semanticsLabel});
  final double value;
  final double size;
  final String? label;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: semanticsLabel != null,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value.clamp(0, 1)),
                duration: shortAnimation,
                builder: (_, v, _) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: c.surfaceHigh,
                  color: c.accent,
                ),
              ),
            ),
            if (label != null) Text(label!, style: numberStyle(context, size * 0.26)),
          ],
        ),
      ),
    );
  }
}

/// Texto com os trechos que casam com a busca destacados.
class HighlightText extends StatelessWidget {
  const HighlightText(this.text, this.query, {super.key, this.style, this.maxLines = 2});
  final String text;
  final String query;
  final TextStyle? style;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final ranges = highlightRanges(text, query);
    final base = style ?? DefaultTextStyle.of(context).style;
    if (ranges.isEmpty) return Text(text, style: base, maxLines: maxLines, overflow: TextOverflow.ellipsis);
    final c = context.colors;
    final spans = <TextSpan>[];
    var i = 0;
    for (final (s, e) in ranges) {
      if (s > i) spans.add(TextSpan(text: text.substring(i, s)));
      spans.add(
        TextSpan(
          text: text.substring(s, e),
          style: TextStyle(backgroundColor: c.accent.withValues(alpha: 0.35), fontWeight: FontWeight.w700),
        ),
      );
      i = e;
    }
    if (i < text.length) spans.add(TextSpan(text: text.substring(i)));
    return Text.rich(
      TextSpan(style: base, children: spans),
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Barra de progresso da checklist com `marcados/total`.
class ChecklistBar extends StatelessWidget {
  const ChecklistBar(this.progress, {super.key});
  final ChecklistProgress progress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Checklist: ${progress.checked} de ${progress.total} itens',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: progress.fraction, minHeight: 6),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            progress.label,
            style: TextStyle(fontSize: 12, fontFeatures: tabular, color: context.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Diálogo de confirmação. Retorna true se confirmou.
Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: ctx.colors.error, foregroundColor: Colors.white)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Pede um texto (renomear, nome do modelo...). Null se cancelou.
Future<String?> askText(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String action = 'Salvar',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(action)),
      ],
    ),
  );
  // Descarta depois da animação de saída do diálogo.
  Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
  return result;
}

void showSnack(BuildContext context, String message, {String? actionLabel, VoidCallback? onAction}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 4),
      action: actionLabel == null ? null : SnackBarAction(label: actionLabel, onPressed: onAction ?? () {}),
    ),
  );
}

/// Mostra carregando / erro / conteúdo de um AsyncValue.
class AsyncView<T> extends StatelessWidget {
  const AsyncView(this.value, {super.key, required this.builder});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      ),
      error: (e, _) => EmptyState(icon: Icons.error_outline, title: 'Algo deu errado', message: '$e'),
      skipLoadingOnReload: true,
      skipLoadingOnRefresh: true,
    );
  }
}
