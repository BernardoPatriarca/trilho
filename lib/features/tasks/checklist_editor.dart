// Editor de checklist: adicionar com Enter (o foco fica no campo), quantidade
// opcional, arrastar para reordenar, marcados vão para baixo riscados, colar
// uma lista cria um item por linha, e o menu (desmarcar todos, remover
// marcados, inserir modelo, salvar como modelo).
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/theme.dart';
import '../../core/data_providers.dart';
import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../../domain/models.dart';
import '../../domain/text.dart';

/// Item em edição (chave estável para animação e reordenação).
class EditableItem {
  EditableItem({this.id, required this.text, this.quantity, this.checked = false}) : key = UniqueKey();
  final Key key;
  int? id;
  String text;
  String? quantity;
  bool checked;

  ChecklistItem toItem(int order) =>
      ChecklistItem(id: id, text: text, quantity: quantity, checked: checked, order: order);

  static EditableItem from(ChecklistItem i) =>
      EditableItem(id: i.id, text: i.text, quantity: i.quantity, checked: i.checked);
}

class ChecklistEditor extends ConsumerStatefulWidget {
  const ChecklistEditor({super.key, required this.items, required this.onChanged, required this.onToggle});
  final List<EditableItem> items;

  /// Lista mudou (adicionou, removeu, reordenou, editou).
  final VoidCallback onChanged;

  /// Item marcado/desmarcado (a tela decide se grava na hora).
  final ValueChanged<EditableItem> onToggle;

  @override
  ConsumerState<ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends ConsumerState<ChecklistEditor> {
  final _text = TextEditingController();
  final _qty = TextEditingController();
  final _focus = FocusNode();
  String _last = '';

  @override
  void dispose() {
    _text.dispose();
    _qty.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<EditableItem> get _items => widget.items;

  void _addItems(List<String> texts, {String? qty}) {
    if (texts.isEmpty) return;
    setState(() {
      // Novos itens entram antes dos marcados.
      final firstChecked = _items.indexWhere((i) => i.checked);
      final at = firstChecked < 0 ? _items.length : firstChecked;
      _items.insertAll(at, [
        for (final (k, t) in texts.indexed) EditableItem(text: t, quantity: k == 0 && texts.length == 1 ? qty : null),
      ]);
    });
    widget.onChanged();
  }

  void _submit() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    final q = _qty.text.trim();
    _addItems([t], qty: q.isEmpty ? null : q);
    _text.clear();
    _qty.clear();
    _last = '';
    // Mantém o teclado aberto para o próximo item.
    _focus.requestFocus();
  }

  /// Colar uma lista: se entrou de uma vez texto com quebra de linha (ou
  /// vírgulas), vira um item por linha.
  void _onTextChanged(String v) {
    final grew = v.length - _last.length;
    // Enter de teclado físico: adiciona o item.
    if (grew == 1 && v.endsWith('\n')) {
      _text.text = v.substring(0, v.length - 1);
      _submit();
      return;
    }
    final pasted = grew > 1 && (v.contains('\n') || v.contains(',') || v.contains(';'));
    _last = v;
    if (!pasted) return;
    final parts = splitPastedList(v);
    if (parts.length < 2) return;
    _text.clear();
    _last = '';
    _addItems(parts);
    showSnack(context, '${parts.length} itens adicionados da lista colada');
  }

  void _toggle(EditableItem it) {
    HapticFeedback.selectionClick();
    setState(() {
      it.checked = !it.checked;
      // Marcados descem para o fim; desmarcados voltam para antes deles.
      _items.remove(it);
      if (it.checked) {
        _items.add(it);
      } else {
        final firstChecked = _items.indexWhere((i) => i.checked);
        _items.insert(firstChecked < 0 ? _items.length : firstChecked, it);
      }
    });
    widget.onToggle(it);
  }

  Future<void> _edit(EditableItem it) async {
    final t = TextEditingController(text: it.text);
    final q = TextEditingController(text: it.quantity ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: t,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Item'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: q,
              decoration: const InputDecoration(labelText: 'Quantidade (opcional)', hintText: '2, 1 kg, 3 un'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() => _items.remove(it));
              widget.onChanged();
              Navigator.pop(ctx, false);
            },
            child: Text('Remover', style: TextStyle(color: ctx.colors.error)),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok == true && t.text.trim().isNotEmpty) {
      setState(() {
        it.text = t.text.trim();
        it.quantity = q.text.trim().isEmpty ? null : q.text.trim();
      });
      widget.onChanged();
    }
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      t.dispose();
      q.dispose();
    });
  }

  Future<void> _menu(String action) async {
    switch (action) {
      case 'desmarcar':
        setState(() {
          for (final i in _items) {
            i.checked = false;
          }
        });
        widget.onChanged();
      case 'remover':
        final n = _items.where((i) => i.checked).length;
        if (n == 0) return;
        setState(() => _items.removeWhere((i) => i.checked));
        widget.onChanged();
        if (mounted) showSnack(context, '$n ite${n == 1 ? 'm removido' : 'ns removidos'}');
      case 'modelo':
        final templates = await ref.read(templatesProvider.future);
        if (!mounted) return;
        if (templates.isEmpty) {
          showSnack(context, 'Nenhum modelo salvo ainda.');
          return;
        }
        final t = await showModalBottomSheet<ChecklistTemplate>(
          context: context,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 8), child: SectionTitle('Inserir modelo')),
                for (final t in templates)
                  ListTile(
                    leading: const Icon(Icons.playlist_add),
                    title: Text(t.name),
                    subtitle: Text('${t.items.length} itens'),
                    onTap: () => Navigator.pop(ctx, t),
                  ),
              ],
            ),
          ),
        );
        if (t == null) return;
        final existing = _items.map((i) => normalizeText(i.text)).toSet();
        final fresh = t.items.where((i) => !existing.contains(normalizeText(i.text))).toList();
        setState(() {
          final firstChecked = _items.indexWhere((i) => i.checked);
          _items.insertAll(firstChecked < 0 ? _items.length : firstChecked, [
            for (final i in fresh) EditableItem(text: i.text, quantity: i.quantity),
          ]);
        });
        widget.onChanged();
        if (mounted) showSnack(context, '${fresh.length} itens de "${t.name}" inseridos');
      case 'salvar':
        if (_items.isEmpty) {
          showSnack(context, 'A checklist está vazia.');
          return;
        }
        final name = await askText(context, title: 'Salvar como modelo', hint: 'Nome do modelo (ex.: Farmácia)');
        if (name == null || name.trim().isEmpty || !mounted) return;
        try {
          await ref
              .read(templateRepositoryProvider)
              .save(
                ChecklistTemplate(
                  name: name,
                  items: [
                    for (final (k, i) in _items.indexed) ChecklistItem(text: i.text, quantity: i.quantity, order: k),
                  ],
                ),
              );
          ref.dataChanged();
          if (mounted) showSnack(context, 'Modelo "${name.trim()}" salvo');
        } on ArgumentError catch (e) {
          if (mounted) showSnack(context, '${e.message}');
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = ChecklistProgress(_items.where((i) => i.checked).length, _items.length);
    final unchecked = _items.where((i) => !i.checked).toList();
    final checked = _items.where((i) => i.checked).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Checklist',
          trailing: PopupMenuButton<String>(
            tooltip: 'Menu da checklist',
            onSelected: _menu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'desmarcar', child: Text('Desmarcar todos')),
              PopupMenuItem(value: 'remover', child: Text('Remover marcados')),
              PopupMenuItem(value: 'modelo', child: Text('Inserir modelo')),
              PopupMenuItem(value: 'salvar', child: Text('Salvar como modelo')),
            ],
          ),
        ),
        if (!progress.isEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: ChecklistBar(progress)),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          onReorderItem: (from, to) {
            setState(() {
              final it = unchecked.removeAt(from);
              unchecked.insert(to, it);
              _items
                ..clear()
                ..addAll([...unchecked, ...checked]);
            });
            widget.onChanged();
          },
          children: [
            for (final (i, it) in unchecked.indexed)
              _ItemRow(
                key: it.key,
                item: it,
                index: i,
                onToggle: () => _toggle(it),
                onEdit: () => _edit(it),
                draggable: true,
              ),
          ],
        ),
        for (final it in checked)
          _ItemRow(key: it.key, item: it, index: -1, onToggle: () => _toggle(it), onEdit: () => _edit(it)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const Key('checklistAdd'),
                controller: _text,
                focusNode: _focus,
                textInputAction: TextInputAction.next,
                textCapitalization: TextCapitalization.sentences,
                // Várias linhas só para o colar preservar as quebras; a tecla de
                // ação do teclado adiciona o item.
                keyboardType: TextInputType.text,
                minLines: 1,
                maxLines: null,
                decoration: const InputDecoration(hintText: 'Adicionar item', prefixIcon: Icon(Icons.add)),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _submit(),
                onEditingComplete: _submit,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: TextField(
                controller: _qty,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(hintText: 'Qtd.'),
                onSubmitted: (_) => _submit(),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Dica: cole uma lista (um item por linha ou separados por vírgula).',
            style: TextStyle(fontSize: 12, color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.index,
    required this.onToggle,
    required this.onEdit,
    this.draggable = false,
  });
  final EditableItem item;
  final int index;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final bool draggable;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = '${item.text}${item.quantity == null ? '' : ', ${item.quantity}'}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: c.surface,
        borderRadius: BorderRadius.circular(14),
        child: Row(
          children: [
            Semantics(
              checked: item.checked,
              label: label,
              child: Checkbox(value: item.checked, onChanged: (_) => onToggle()),
            ),
            Expanded(
              child: InkWell(
                onTap: onToggle,
                onLongPress: onEdit,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedDefaultTextStyle(
                      duration: shortAnimation,
                      style: TextStyle(
                        fontSize: 15,
                        color: item.checked ? c.textSecondary : c.text,
                        decoration: item.checked ? TextDecoration.lineThrough : TextDecoration.none,
                        fontFamily: bodyFont,
                      ),
                      child: Text(item.text),
                    ),
                  ),
                ),
              ),
            ),
            if (item.quantity != null)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: c.surfaceHigh, borderRadius: BorderRadius.circular(8)),
                child: Text(item.quantity!, style: const TextStyle(fontSize: 12, fontFeatures: tabular)),
              ),
            IconButton(tooltip: 'Editar item', icon: const Icon(Icons.edit_outlined, size: 18), onPressed: onEdit),
            if (draggable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_handle, color: c.textSecondary, semanticLabel: 'Arrastar para reordenar'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
