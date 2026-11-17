// Prioridade das tarefas (P1 = Urgente ... P4 = Baixa). Regra pura, sem Flutter.

enum Priority {
  p1(1, 'Urgente'),
  p2(2, 'Alta'),
  p3(3, 'Média'),
  p4(4, 'Baixa');

  const Priority(this.value, this.label);

  /// Valor gravado na coluna `tarefa.prioridade` (1 a 4).
  final int value;

  /// Nome exibido junto da cor (a prioridade nunca é indicada só pela cor).
  final String label;

  /// Rótulo curto: "P1".
  String get code => 'P$value';

  static Priority fromValue(int value) =>
      Priority.values.firstWhere((p) => p.value == value, orElse: () => Priority.p4);
}
