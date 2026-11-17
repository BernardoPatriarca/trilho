// Parser da adição rápida em linguagem natural (pt-BR), regra 6.7.
//
// Exemplo: "Mercado amanhã 18h #casa !2 @compras"
//   título "Mercado", amanhã às 18:00, tag "casa", P2, categoria Compras.
//
// Reconhece datas (hoje, amanhã, depois de amanhã, dias da semana, dd/mm,
// dd/mm/aaaa, dia 25), horas (18h, 18:30, às 9, 9h30), recorrência simples
// (todo dia, toda segunda, toda semana, todo mês, todo dia 10), @categoria,
// #tag e !1..!4. O que sobra vira o título.
import 'dates.dart';
import 'models.dart';
import 'recurrence.dart';
import 'text.dart';

enum TokenKind { date, time, recurrence, category, tag, priority, event }

/// Um trecho reconhecido (vira chip na tela).
class RecognizedToken {
  const RecognizedToken(this.kind, this.raw, this.label);
  final TokenKind kind;

  /// Texto original que gerou o reconhecimento (chave para "remover o chip").
  final String raw;
  final String label;
}

class QuickAddResult {
  const QuickAddResult({
    required this.title,
    this.date,
    this.minutes,
    this.rule,
    this.categoryId,
    this.tags = const [],
    this.priority,
    this.isEvent = false,
    this.tokens = const [],
  });

  final String title;
  final DateTime? date;
  final int? minutes;
  final RecurrenceRule? rule;
  final int? categoryId;
  final List<String> tags;
  final int? priority;

  /// Pediu evento com a palavra "evento" + horário.
  final bool isEvent;
  final List<RecognizedToken> tokens;
}

class _Tok {
  _Tok(this.raw) : norm = normalizeText(raw);
  final String raw;
  final String norm;
}

const _weekdays = {
  'segunda': 1,
  'terca': 2,
  'quarta': 3,
  'quinta': 4,
  'sexta': 5,
  'sabado': 6,
  'domingo': 7,
};

int? _weekday(String norm) {
  final n = norm.replaceAll(RegExp(r'[.,;!?]+$'), '');
  final base = n.endsWith('-feira') ? n.substring(0, n.length - 6) : n;
  return _weekdays[base];
}

/// Remove pontuação final ("amanhã," → "amanha").
String _clean(String norm) => norm.replaceAll(RegExp(r'[.,;!?]+$'), '');

const _prepositions = {'na', 'no', 'em', 'para', 'pra', 'ate', 'de'};

/// [categories]: categorias ativas (para `@nome`). [ignored]: textos de
/// chips que o usuário removeu (ficam no título).
QuickAddResult parseQuickAdd(
  String input,
  DateTime now, {
  List<Category> categories = const [],
  Set<String> ignored = const {},
}) {
  final today = dateOnly(now);
  final toks = input.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).map(_Tok.new).toList();
  final used = List<bool>.filled(toks.length, false);
  final tokens = <RecognizedToken>[];

  DateTime? date;
  int? minutes;
  RecurrenceRule? rule;
  int? categoryId;
  final tags = <String>[];
  int? priority;
  var eventWord = false;
  var eventIdx = -1;

  String rawOf(int i, int n) => toks.sublist(i, i + n).map((t) => t.raw).join(' ');
  bool free(int i, int n) {
    if (i + n > toks.length) return false;
    for (var k = i; k < i + n; k++) {
      if (used[k]) return false;
    }
    return !ignored.contains(rawOf(i, n));
  }

  void mark(int i, int n, TokenKind kind, String label) {
    for (var k = i; k < i + n; k++) {
      used[k] = true;
    }
    tokens.add(RecognizedToken(kind, rawOf(i, n), label));
  }

  String norm(int i) => i < toks.length ? _clean(toks[i].norm) : '';

  // Absorve uma preposição solta antes de data/hora ("na sexta", "às 9").
  void absorbPreposition(int i) {
    if (i > 0 && !used[i - 1] && _prepositions.contains(norm(i - 1))) {
      used[i - 1] = true;
    }
  }

  // 1ª passada: frases de várias palavras (recorrência e datas compostas).
  for (var i = 0; i < toks.length; i++) {
    if (used[i]) continue;
    final w = norm(i);

    if ((w == 'todo' || w == 'toda' || w == 'todos' || w == 'todas') && rule == null) {
      final w1 = norm(i + 1);
      // "todo dia 10"
      if (w == 'todo' && w1 == 'dia' && free(i, 3)) {
        final d = int.tryParse(norm(i + 2));
        if (d != null && d >= 1 && d <= 31) {
          final start = _nextDayOfMonth(today, d);
          rule = const RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDoMes);
          date ??= start;
          mark(i, 3, TokenKind.recurrence, 'Todo dia $d');
          continue;
        }
      }
      // "todos os dias"
      if (w == 'todos' && w1 == 'os' && norm(i + 2) == 'dias' && free(i, 3)) {
        rule = const RecurrenceRule(freq: Freq.diaria);
        mark(i, 3, TokenKind.recurrence, 'Todo dia');
        continue;
      }
      if (w == 'todo' && w1 == 'dia' && free(i, 2)) {
        rule = const RecurrenceRule(freq: Freq.diaria);
        mark(i, 2, TokenKind.recurrence, 'Todo dia');
        continue;
      }
      if (w == 'toda' && w1 == 'semana' && free(i, 2)) {
        rule = const RecurrenceRule(freq: Freq.semanal);
        mark(i, 2, TokenKind.recurrence, 'Toda semana');
        continue;
      }
      if (w == 'todo' && (w1 == 'mes') && free(i, 2)) {
        rule = const RecurrenceRule(freq: Freq.mensal, monthlyMode: MonthlyMode.diaDoMes);
        mark(i, 2, TokenKind.recurrence, 'Todo mês');
        continue;
      }
      if (w == 'todo' && w1 == 'ano' && free(i, 2)) {
        rule = const RecurrenceRule(freq: Freq.anual);
        mark(i, 2, TokenKind.recurrence, 'Todo ano');
        continue;
      }
      final wd = _weekday(w1);
      if (wd != null && free(i, 2)) {
        rule = RecurrenceRule(freq: Freq.semanal, weekdays: [wd]);
        // A primeira ocorrência pode ser hoje.
        date ??= today.weekday == wd ? today : nextWeekday(today, wd);
        final label = wd >= 6 ? 'Todo ${weekdayLong[wd]}' : 'Toda ${weekdayLong[wd]}';
        mark(i, 2, TokenKind.recurrence, label);
        continue;
      }
    }

    if (date == null && w == 'depois' && norm(i + 1) == 'de' && norm(i + 2) == 'amanha' && free(i, 3)) {
      date = addDays(today, 2);
      absorbPreposition(i);
      mark(i, 3, TokenKind.date, _dateLabel(date, today));
      continue;
    }

    // "dia 25"
    if (date == null && w == 'dia' && free(i, 2)) {
      final d = int.tryParse(norm(i + 1));
      if (d != null && d >= 1 && d <= 31) {
        date = _nextDayOfMonth(today, d);
        absorbPreposition(i);
        mark(i, 2, TokenKind.date, _dateLabel(date, today));
        continue;
      }
    }

    // "às 9", "as 18:30", "às 9h"
    if (minutes == null && (w == 'as' || w == 'a') && free(i, 2)) {
      final m = _parseTime(norm(i + 1), bare: true);
      if (m != null) {
        minutes = m;
        mark(i, 2, TokenKind.time, minutesToHm(m));
        continue;
      }
    }
  }

  // 2ª passada: palavras soltas.
  for (var i = 0; i < toks.length; i++) {
    if (used[i] || !free(i, 1)) continue;
    final raw = toks[i].raw;
    final w = norm(i);

    if (date == null && (w == 'hoje' || w == 'amanha')) {
      date = w == 'hoje' ? today : addDays(today, 1);
      absorbPreposition(i);
      mark(i, 1, TokenKind.date, _dateLabel(date, today));
      continue;
    }
    if (date == null) {
      final wd = _weekday(w);
      if (wd != null) {
        date = nextWeekday(today, wd);
        absorbPreposition(i);
        mark(i, 1, TokenKind.date, _dateLabel(date, today));
        continue;
      }
      final d = _parseDayMonth(w, today);
      if (d != null) {
        date = d;
        absorbPreposition(i);
        mark(i, 1, TokenKind.date, _dateLabel(d, today));
        continue;
      }
    }
    if (minutes == null) {
      final m = _parseTime(w);
      if (m != null) {
        minutes = m;
        absorbPreposition(i);
        mark(i, 1, TokenKind.time, minutesToHm(m));
        continue;
      }
    }
    if (raw.startsWith('!') && priority == null) {
      final p = int.tryParse(raw.substring(1));
      if (p != null && p >= 1 && p <= 4) {
        priority = p;
        mark(i, 1, TokenKind.priority, 'P$p · ${const ['', 'Urgente', 'Alta', 'Média', 'Baixa'][p]}');
        continue;
      }
    }
    if (raw.startsWith('@') && raw.length > 1 && categoryId == null) {
      final name = normalizeText(raw.substring(1)).replaceAll(RegExp(r'[.,;!?]+$'), '');
      final match = categories.where((c) => normalizeText(c.name) == name).firstOrNull;
      if (match != null) {
        categoryId = match.id;
        mark(i, 1, TokenKind.category, '@${match.name}');
        continue;
      }
    }
    if (raw.startsWith('#') && raw.length > 1) {
      final tag = normalizeTagName(raw).replaceAll(RegExp(r'[.,;!?]+$'), '');
      if (tag.isNotEmpty) {
        if (!tags.contains(tag)) tags.add(tag);
        mark(i, 1, TokenKind.tag, '#$tag');
        continue;
      }
    }
    if (w == 'evento' && !eventWord) {
      eventWord = true;
      eventIdx = i;
    }
  }

  // "evento" só vale com horário; sem horário continua no título.
  final isEvent = eventWord && minutes != null;
  if (isEvent) mark(eventIdx, 1, TokenKind.event, 'Evento');

  // Hora sem data: hoje. Recorrência sem data: hoje (ou a próxima válida).
  if (minutes != null && date == null) date = today;
  if (rule != null && date == null) date = today;
  if (rule != null && rule.freq == Freq.semanal && rule.weekdays.isEmpty && date != null) {
    rule = rule.copyWith(weekdays: [date.weekday]);
  }

  final title = [
    for (var i = 0; i < toks.length; i++)
      if (!used[i]) toks[i].raw,
  ].join(' ').trim();

  // Mantém os chips na ordem em que aparecem no texto.
  final order = {for (final (i, t) in toks.indexed) t.raw: i};
  tokens.sort((a, b) => (order[a.raw.split(' ').first] ?? 0).compareTo(order[b.raw.split(' ').first] ?? 0));

  return QuickAddResult(
    title: title,
    date: date,
    minutes: minutes,
    rule: rule,
    categoryId: categoryId,
    tags: tags,
    priority: priority,
    isEvent: isEvent,
    tokens: [
      ...tokens,
    ],
  );
}

/// Próxima data com o dia [d] (este mês se ainda não passou), pulando meses
/// curtos.
DateTime _nextDayOfMonth(DateTime today, int d) {
  var y = today.year, m = today.month;
  for (var k = 0; k < 24; k++) {
    if (d <= daysInMonth(y, m)) {
      final c = DateTime(y, m, d);
      if (!c.isBefore(today)) return c;
    }
    m++;
    if (m > 12) {
      m = 1;
      y++;
    }
  }
  return today;
}

/// dd/mm ou dd/mm/aaaa (ou aa). Sem ano e já passado: ano que vem.
DateTime? _parseDayMonth(String w, DateTime today) {
  final m = RegExp(r'^(\d{1,2})/(\d{1,2})(?:/(\d{2}|\d{4}))?$').firstMatch(w);
  if (m == null) return null;
  final d = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  if (mo < 1 || mo > 12) return null;
  var y = today.year;
  final ys = m.group(3);
  if (ys != null) {
    y = int.parse(ys);
    if (ys.length == 2) y += 2000;
  }
  if (d < 1 || d > daysInMonth(y, mo)) return null;
  var date = DateTime(y, mo, d);
  if (ys == null && date.isBefore(today)) {
    if (d > daysInMonth(y + 1, mo)) return null;
    date = DateTime(y + 1, mo, d);
  }
  return date;
}

/// 18h, 18h30, 9h30, 18:30. Com [bare], aceita número solto ("às 9").
int? _parseTime(String w, {bool bare = false}) {
  var m = RegExp(r'^(\d{1,2})h(\d{2})?$').firstMatch(w) ??
      RegExp(r'^(\d{1,2}):(\d{2})h?$').firstMatch(w);
  if (m == null && bare) m = RegExp(r'^(\d{1,2})()$').firstMatch(w);
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final g2 = m.group(2);
  final min = g2 == null || g2.isEmpty ? 0 : int.parse(g2);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

String _dateLabel(DateTime d, DateTime today) {
  final diff = daysBetween(today, d);
  final base = dayMonth(d);
  if (diff == 0) return 'Hoje, $base';
  if (diff == 1) return 'Amanhã, $base';
  return '${_cap(weekdayShort[d.weekday])}, $base';
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Descrição da recorrência reconhecida (para o chip e o formulário).
String? describeQuickRule(QuickAddResult r) =>
    r.rule == null || r.date == null ? null : describeRecurrence(r.rule!, r.date!);
