// Mais › Modelos de checklist: criar, editar itens (com quantidade) e excluir.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';

class TemplatesPage extends ConsumerWidget {
  const TemplatesPage({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [ChecklistTemplate? t]) async {
    final result = await Navigator.of(context)
        .push<ChecklistTemplate>(MaterialPageRoute(builder: (_) => _TemplateForm(initial: t)));
    if (result == null) return;
    try {
      await ref.read(templateRepositoryProvider).save(result);
      ref.dataChanged();
    } on ArgumentError catch (e) {
      if (context.mounted) showSnack(context, '${e.message}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(templatesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('MODELOS DE CHECKLIST')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('Novo modelo'),
      ),
      body: AsyncView(
        list,
        builder: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.playlist_add_check,
              title: 'Nenhum modelo',
              message: 'Crie um aqui ou use "Salvar como modelo" no menu da checklist de uma tarefa.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
            children: [
              for (final t in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: const Icon(Icons.playlist_add_check),
                      title: Text(t.name),
                      subtitle: Text(
                        t.items.isEmpty
                            ? 'Vazio'
                            : t.items.take(5).map((i) => i.text).join(', ') + (t.items.length > 5 ? '…' : ''),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _edit(context, ref, t),
                      trailing: IconButton(
                        tooltip: 'Excluir modelo',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: 'Excluir "${t.name}"?',
                            confirmLabel: 'Excluir',
                            destructive: true,
                          );
                          if (!ok) return;
                          await ref.read(templateRepositoryProvider).delete(t.id!);
                          ref.dataChanged();
                        },
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

class _TemplateForm extends StatefulWidget {
  const _TemplateForm({this.initial});
  final ChecklistTemplate? initial;

  @override
  State<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends State<_TemplateForm> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  final _item = TextEditingController();
  final _focus = FocusNode();
  late final List<ChecklistItem> _items = [...?widget.initial?.items];
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _item.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _add() {
    final parts = splitPastedList(_item.text);
    if (parts.isEmpty) return;
    setState(() => _items.addAll(parts.map((p) => ChecklistItem(text: p))));
    _item.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? 'NOVO MODELO' : 'EDITAR MODELO')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
        children: [
          TextField(
            controller: _name,
            autofocus: widget.initial == null,
            decoration: InputDecoration(labelText: 'Nome do modelo', errorText: _error),
          ),
          const SectionTitle('Itens'),
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (from, to) => setState(() {
              _items.insert(to, _items.removeAt(from));
            }),
            children: [
              for (final (i, it) in _items.indexed)
                Padding(
                  key: ObjectKey(it),
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    child: ListTile(
                      dense: true,
                      title: Text(it.text),
                      subtitle: it.quantity == null ? null : Text(it.quantity!),
                      onTap: () async {
                        final q = await askText(
                          context,
                          title: 'Quantidade de "${it.text}"',
                          initial: it.quantity ?? '',
                          hint: '2, 1 kg, 3 un',
                        );
                        if (q != null) {
                          setState(() => _items[i] = it.copyWith(quantity: q.trim(), clearQuantity: q.trim().isEmpty));
                        }
                      },
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Remover',
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _items.removeAt(i)),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle, semanticLabel: 'Arrastar'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _item,
            focusNode: _focus,
            minLines: 1,
            maxLines: null,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'Adicionar item (ou cole uma lista)',
              suffixIcon: IconButton(tooltip: 'Adicionar', icon: const Icon(Icons.add), onPressed: _add),
            ),
            onSubmitted: (_) => _add(),
            onEditingComplete: _add,
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: FilledButton(
            onPressed: () {
              if (_name.text.trim().isEmpty) {
                setState(() => _error = 'Informe o nome do modelo.');
                return;
              }
              Navigator.pop(
                context,
                ChecklistTemplate(
                  id: widget.initial?.id,
                  name: _name.text.trim(),
                  items: [for (final (i, it) in _items.indexed) it.copyWith(order: i)],
                ),
              );
            },
            child: const Text('Salvar modelo'),
          ),
        ),
      ),
    );
  }
}
