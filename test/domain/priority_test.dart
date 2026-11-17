import 'package:flutter_test/flutter_test.dart';
import 'package:trilho/domain/priority.dart';

void main() {
  test('prioridades têm código, nome e valor do banco', () {
    expect(Priority.values.map((p) => '${p.code} ${p.label}'),
        ['P1 Urgente', 'P2 Alta', 'P3 Média', 'P4 Baixa']);
    expect(Priority.fromValue(1), Priority.p1);
    expect(Priority.fromValue(4), Priority.p4);
  });

  test('valor desconhecido cai em Baixa (padrão do banco)', () {
    expect(Priority.fromValue(0), Priority.p4);
    expect(Priority.fromValue(9), Priority.p4);
  });
}
