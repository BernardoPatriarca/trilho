// Widgets reutilizados por várias telas.
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../domain/priority.dart';

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
          ?trailing,
        ],
      ),
    );
  }
}

/// Cartão padrão (superfície com borda e cantos de 20 px).
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
  });

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
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

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
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, height: 1.4),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
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
    final label =
        compact ? priority.code : '${priority.code} · ${priority.label}';
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
