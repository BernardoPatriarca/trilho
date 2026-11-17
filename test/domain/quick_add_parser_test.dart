import 'package:flutter_test/flutter_test.dart';
import 'package:trilho/domain/models.dart';
import 'package:trilho/domain/quick_add_parser.dart';

// Terça-feira, 17/11/2026, 09:00.
final now = DateTime(2026, 11, 17, 9);
DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);

const cats = [
  Category(id: 1, name: 'Trabalho', color: '#000000', icon: 'work'),
  Category(id: 7, name: 'Compras', color: '#000000', icon: 'shopping_cart'),
  Category(id: 5, name: 'Saúde', color: '#000000', icon: 'favorite'),
  Category(id: 6, name: 'Finanças', color: '#000000', icon: 'payments'),
];

QuickAddResult p(String s, {Set<String> ignored = const {}}) =>
    parseQuickAdd(s, now, categories: cats, ignored: ignored);

void main() {
  test('exemplo da especificação', () {
    final r = p('Mercado amanhã 18h #casa !2 @compras');
    expect(r.title, 'Mercado');
    expect(r.date, d(11, 18));
    expect(r.minutes, 18 * 60);
    expect(r.tags, ['casa']);
    expect(r.priority, 2);
    expect(r.categoryId, 7);
    expect(r.isEvent, isFalse);
    expect(r.tokens.map((t) => t.kind).toSet(), {
      TokenKind.date,
      TokenKind.time,
      TokenKind.tag,
      TokenKind.priority,
      TokenKind.category,
    });
  });

  test('texto simples vira só título', () {
    final r = p('Prender o varão na parede');
    expect(r.title, 'Prender o varão na parede');
    expect(r.date, isNull);
    expect(r.minutes, isNull);
    expect(r.tokens, isEmpty);
  });

  group('datas', () {
    test('hoje', () => expect(p('Ligar hoje').date, d(11, 17)));
    test('amanhã', () => expect(p('Ligar amanhã').date, d(11, 18)));
    test('amanha sem acento', () => expect(p('Ligar amanha').date, d(11, 18)));
    test('AMANHÃ maiúsculo', () => expect(p('Ligar AMANHÃ').date, d(11, 18)));
    test('depois de amanhã', () {
      final r = p('Pagar conta depois de amanhã');
      expect(r.date, d(11, 19));
      expect(r.title, 'Pagar conta');
    });
    test('dia da semana é a próxima ocorrência', () => expect(p('Reunião sexta').date, d(11, 20)));
    test('mesmo dia da semana vai para a semana seguinte', () => expect(p('Feira terça').date, d(11, 24)));
    test('sábado com acento e "no"', () {
      final r = p('Churrasco no sábado');
      expect(r.date, d(11, 21));
      expect(r.title, 'Churrasco');
    });
    test('segunda-feira', () => expect(p('Academia segunda-feira').date, d(11, 23)));
    test('dd/mm', () => expect(p('Consulta 25/12').date, d(12, 25)));
    test('dd/mm já passado vai para o ano que vem', () => expect(p('Aniversário 10/03').date, d(3, 10, 2027)));
    test('dd/mm/aaaa', () => expect(p('Prova 05/01/2027').date, d(1, 5, 2027)));
    test('dd/mm/aa', () => expect(p('Prova 05/01/27').date, d(1, 5, 2027)));
    test('data inválida fica no título', () {
      final r = p('Código 31/02');
      expect(r.date, isNull);
      expect(r.title, 'Código 31/02');
    });
    test('dia 25 deste mês', () => expect(p('Aluguel dia 25').date, d(11, 25)));
    test('dia 10 já passou: mês que vem', () => expect(p('Aluguel dia 10').date, d(12, 10)));
  });

  group('horas', () {
    test('18h', () => expect(p('Mercado 18h').minutes, 18 * 60));
    test('18:30', () => expect(p('Mercado 18:30').minutes, 18 * 60 + 30));
    test('às 9', () {
      final r = p('Dentista às 9');
      expect(r.minutes, 9 * 60);
      expect(r.title, 'Dentista');
    });
    test('as 9 sem acento', () => expect(p('Dentista as 9').minutes, 9 * 60));
    test('9h30', () => expect(p('Café 9h30').minutes, 9 * 60 + 30));
    test('hora sem data é hoje', () => expect(p('Café 9h30').date, d(11, 17)));
    test('25h não é hora', () {
      final r = p('Jogo 25h');
      expect(r.minutes, isNull);
      expect(r.title, 'Jogo 25h');
    });
  });

  group('recorrência', () {
    test('todo dia', () {
      final r = p('Tomar remédio todo dia 8h');
      expect(r.rule!.freq, Freq.diaria);
      expect(r.minutes, 8 * 60);
      expect(r.title, 'Tomar remédio');
      expect(r.date, d(11, 17));
    });
    test('toda segunda', () {
      final r = p('Lista do mercado toda segunda');
      expect(r.rule!.freq, Freq.semanal);
      expect(r.rule!.weekdays, [1]);
      expect(r.date, d(11, 23));
      expect(r.title, 'Lista do mercado');
    });
    test('toda terça começa hoje (terça)', () => expect(p('Feira toda terça').date, d(11, 17)));
    test('toda semana usa o dia da data', () {
      final r = p('Faxina toda semana sexta');
      expect(r.rule!.freq, Freq.semanal);
      expect(r.date, d(11, 20));
      expect(r.rule!.weekdays, [5]);
    });
    test('todo mês', () => expect(p('Fatura todo mês').rule!.freq, Freq.mensal));
    test('todo mes sem acento', () => expect(p('Fatura todo mes').rule!.freq, Freq.mensal));
    test('todo dia 10', () {
      final r = p('Pagar aluguel todo dia 10');
      expect(r.rule!.freq, Freq.mensal);
      expect(r.rule!.monthlyMode, MonthlyMode.diaDoMes);
      expect(r.date, d(12, 10));
      expect(r.title, 'Pagar aluguel');
    });
  });

  group('categoria, tags e prioridade', () {
    test('@categoria sem acento e maiúscula', () => expect(p('Exame @SAUDE').categoryId, 5));
    test('@categoria com acento', () => expect(p('Boleto @finanças').categoryId, 6));
    test('@desconhecida fica no título', () {
      final r = p('Ver @fulano');
      expect(r.categoryId, isNull);
      expect(r.title, 'Ver @fulano');
    });
    test('várias tags minúsculas e sem repetir', () {
      final r = p('Pintar #Casa #reforma #casa');
      expect(r.tags, ['casa', 'reforma']);
      expect(r.title, 'Pintar');
    });
    test('!1 a !4', () {
      expect(p('X !1').priority, 1);
      expect(p('X !4').priority, 4);
    });
    test('!5 não é prioridade', () {
      final r = p('Nota !5');
      expect(r.priority, isNull);
      expect(r.title, 'Nota !5');
    });
  });

  group('evento', () {
    test('palavra evento + horário cria evento', () {
      final r = p('Evento aniversário da Ana sábado 20h');
      expect(r.isEvent, isTrue);
      expect(r.title, 'aniversário da Ana');
      expect(r.date, d(11, 21));
      expect(r.minutes, 20 * 60);
    });
    test('evento sem horário continua tarefa e fica no título', () {
      final r = p('Planejar evento da firma');
      expect(r.isEvent, isFalse);
      expect(r.title, 'Planejar evento da firma');
    });
  });

  test('chip removido volta para o título', () {
    final r = p('Comprar pão amanhã 18h', ignored: {'amanhã'});
    expect(r.date, d(11, 17)); // hora sem data → hoje
    expect(r.title, 'Comprar pão amanhã');
  });

  test('combinação completa em qualquer ordem', () {
    final r = p('!1 @trabalho Entregar relatório do TCC 05/12 às 14:30 #tcc');
    expect(r.priority, 1);
    expect(r.categoryId, 1);
    expect(r.date, d(12, 5));
    expect(r.minutes, 14 * 60 + 30);
    expect(r.tags, ['tcc']);
    expect(r.title, 'Entregar relatório do TCC');
  });
}
