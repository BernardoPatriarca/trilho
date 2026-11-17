// Mais › Categorias (criar, editar cor e ícone, reordenar, desativar) e
// Mais › Tags (renomear, mesclar, excluir).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/utils/icons.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Category? c]) async {
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CategoryForm(initial: c),
    );
    if (result == null) return;
    try {
      await ref.read(categoryRepositoryProvider).save(result);
      ref.dataChanged();
    } on ArgumentError catch (e) {
      if (context.mounted) showSnack(context, '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('CATEGORIAS')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Nova categoria'),
      ),
      body: AsyncView(
        cats,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.folder_outlined,
              title: 'Nenhuma categoria',
              message: 'Toque em "Nova categoria".',
            );
          }
          return ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            buildDefaultDragHandles: false,
            itemCount: list.length,
            onReorderItem: (from, to) async {
              final ids = list.map((c) => c.id!).toList();
              ids.insert(to, ids.removeAt(from));
              await ref.read(categoryRepositoryProvider).reorder(ids);
              ref.dataChanged();
            },
            itemBuilder: (context, i) {
              final c = list[i];
              final col = context.colors;
              return Padding(
                key: ValueKey(c.id),
                padding: const EdgeInsets.only(bottom: 8),
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: hexColor(c.color).withValues(alpha: 0.25),
                      child: Icon(categoryIcon(c.icon), color: hexColor(c.color)),
                    ),
                    title: Text(c.name, style: TextStyle(color: c.active ? col.text : col.textSecondary)),
                    subtitle: Text(c.active ? 'Ativa' : 'Desativada'),
                    onTap: () => _edit(context, ref, c),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: c.active,
                          onChanged: (v) async {
                            await ref.read(categoryRepositoryProvider).setActive(c.id!, v);
                            ref.dataChanged();
                          },
                        ),
                        ReorderableDragStartListener(
                          index: i,
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Icon(
                              Icons.drag_handle,
                              color: col.textSecondary,
                              semanticLabel: 'Arrastar para reordenar',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryForm extends StatefulWidget {
  const _CategoryForm({this.initial});
  final Category? initial;

  @override
  State<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends State<_CategoryForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late String _color = widget.initial?.color ?? categoryPalette.first;
  late String _icon = widget.initial?.icon ?? 'star';
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.initial == null ? 'NOVA CATEGORIA' : 'EDITAR CATEGORIA',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _name,
              autofocus: widget.initial == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(labelText: 'Nome', errorText: _error),
            ),
            const SectionTitle('Cor'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in categoryPalette)
                  Semantics(
                    button: true,
                    selected: _color == hex,
                    label: 'Cor $hex',
                    child: InkResponse(
                      onTap: () => setState(() => _color = hex),
                      radius: 24,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: hexColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(color: _color == hex ? c.text : Colors.transparent, width: 3),
                        ),
                        child: _color == hex ? const Icon(Icons.check, color: Color(0xFF12161C)) : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SectionTitle('Ícone'),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final e in categoryIcons.entries)
                  IconButton(
                    tooltip: e.key,
                    isSelected: _icon == e.key,
                    style: IconButton.styleFrom(
                      backgroundColor: _icon == e.key ? hexColor(_color).withValues(alpha: 0.3) : null,
                    ),
                    icon: Icon(e.value, color: _icon == e.key ? hexColor(_color) : c.textSecondary),
                    onPressed: () => setState(() => _icon = e.key),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                if (_name.text.trim().isEmpty) {
                  setState(() => _error = 'Informe o nome da categoria.');
                  return;
                }
                final base = widget.initial ?? const Category(name: '', color: '#000000', icon: 'star');
                Navigator.pop(context, base.copyWith(name: _name.text.trim(), color: _color, icon: _icon));
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

class TagsPage extends ConsumerWidget {
  const TagsPage({super.key});

  Future<void> _rename(BuildContext context, WidgetRef ref, Tag t) async {
    final name = await askText(context, title: 'Renomear #${t.name}', initial: t.name);
    if (name == null) return;
    try {
      await ref.read(tagRepositoryProvider).rename(t.id!, name);
      ref.dataChanged();
    } on ArgumentError catch (e) {
      if (context.mounted) showSnack(context, '${e.message}');
    }
  }

  Future<void> _merge(BuildContext context, WidgetRef ref, Tag t, List<Tag> all) async {
    final into = await showModalBottomSheet<Tag>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: SectionTitle('Mesclar #${t.name} em…')),
            for (final o in all.where((o) => o.id != t.id))
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: Text('#${o.name}'),
                onTap: () => Navigator.pop(ctx, o),
              ),
          ],
        ),
      ),
    );
    if (into == null || !context.mounted) return;
    final ok = await confirm(
      context,
      title: 'Mesclar tags?',
      message: 'Tudo marcado com #${t.name} passa para #${into.name}, e #${t.name} some.',
      confirmLabel: 'Mesclar',
    );
    if (!ok) return;
    await ref.read(tagRepositoryProvider).merge(t.id!, into.id!);
    ref.dataChanged();
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Tag t) async {
    final ok = await confirm(
      context,
      title: 'Excluir #${t.name}?',
      message: 'A tag sai de todas as tarefas e eventos.',
      confirmLabel: 'Excluir',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(tagRepositoryProvider).delete(t.id!);
    ref.dataChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider);
    final usage = ref.watch(tagUsageProvider).value ?? const <int, int>{};
    return Scaffold(
      appBar: AppBar(title: const Text('TAGS')),
      body: AsyncView(
        tags,
        builder: (list) {
          if (list.isEmpty) {
            return const EmptyState(
              icon: Icons.tag,
              title: 'Nenhuma tag ainda',
              message: 'Escreva #nome na adição rápida ou no formulário e a tag é criada na hora.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              for (final t in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.tag),
                      title: Text(t.name),
                      subtitle: Text('${usage[t.id] ?? 0} ite${(usage[t.id] ?? 0) == 1 ? 'm' : 'ns'}'),
                      onTap: () => _rename(context, ref, t),
                      trailing: PopupMenuButton<String>(
                        tooltip: 'Ações da tag',
                        onSelected: (a) => switch (a) {
                          'renomear' => _rename(context, ref, t),
                          'mesclar' => _merge(context, ref, t, list),
                          _ => _delete(context, ref, t),
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'renomear', child: Text('Renomear')),
                          if (list.length > 1) const PopupMenuItem(value: 'mesclar', child: Text('Mesclar em…')),
                          const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
