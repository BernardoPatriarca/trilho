// Normalização de texto para busca: minúsculo e sem acento, caractere a
// caractere (o tamanho não muda, então os índices servem para destacar o
// termo no texto original).

const _from = 'áàâãäåéèêëíìîïóòôõöúùûüçñýÿ';
const _to = 'aaaaaaeeeeiiiiooooouuuucnyy';

final Map<int, int> _map = {
  for (var i = 0; i < _from.length; i++) _from.codeUnitAt(i): _to.codeUnitAt(i),
};

String normalizeText(String s) {
  final lower = s.toLowerCase();
  final out = StringBuffer();
  for (final unit in lower.codeUnits) {
    out.writeCharCode(_map[unit] ?? unit);
  }
  return out.toString();
}

/// Texto da coluna `busca`: partes normalizadas separadas por espaço.
String searchIndex(Iterable<String?> parts) => normalizeText(parts
    .where((p) => p != null && p.trim().isNotEmpty)
    .map((p) => p!.trim())
    .join(' '));

/// Palavras do termo (normalizadas). Todas precisam aparecer no índice.
List<String> searchTerms(String query) => normalizeText(query)
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

bool matchesSearch(String index, String query) {
  final terms = searchTerms(query);
  return terms.every(index.contains);
}

/// Trechos de [text] que casam com alguma palavra de [query] (sem acento e
/// sem diferenciar maiúsculas), para destacar no resultado.
List<(int, int)> highlightRanges(String text, String query) {
  final terms = searchTerms(query);
  if (terms.isEmpty) return const [];
  final norm = normalizeText(text);
  final ranges = <(int, int)>[];
  for (final t in terms) {
    var i = norm.indexOf(t);
    while (i >= 0) {
      ranges.add((i, i + t.length));
      i = norm.indexOf(t, i + t.length);
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  // Junta trechos sobrepostos.
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// Nome de tag: sem '#', minúsculo, sem espaços nas pontas.
String normalizeTagName(String s) {
  var t = s.trim();
  while (t.startsWith('#')) {
    t = t.substring(1);
  }
  return t.toLowerCase();
}

/// "colar uma lista": um item por linha ou separados por vírgula/ponto e
/// vírgula. Remove marcadores comuns ("- ", "* ", "• ", "[ ] ", "1. ").
List<String> splitPastedList(String text) {
  final byLine = text.contains('\n');
  final parts = byLine ? text.split(RegExp(r'\r?\n')) : text.split(RegExp(r'[;,]'));
  return parts
      .map((p) => p
          .trim()
          .replaceFirst(RegExp(r'^(\[[ xX]?\]|[-*•·]|\d+[.)])\s*'), '')
          .trim())
      .where((p) => p.isNotEmpty)
      .toList();
}

/// Plural simples: "1 tarefa", "3 tarefas".
String plural(int n, String singular, [String? pluralForm]) =>
    '$n ${n == 1 ? singular : (pluralForm ?? '${singular}s')}';
