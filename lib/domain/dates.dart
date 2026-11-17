// Datas puras: formatos do banco e aritmética de calendário (sem Flutter).
//
// No banco: data em `AAAA-MM-DD`, data e hora em `AAAA-MM-DDTHH:mm` (hora
// local), hora sozinha em `HH:mm`. Em memória, a hora sozinha é um `int` com
// os minutos desde a meia-noite.

String _two(int n) => n.toString().padLeft(2, '0');

/// Só a data (meia-noite local).
DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// `AAAA-MM-DD`
String toIsoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

DateTime fromIsoDate(String s) {
  final p = s.substring(0, 10).split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// `AAAA-MM-DDTHH:mm`
String toIsoDateTime(DateTime d) => '${toIsoDate(d)}T${_two(d.hour)}:${_two(d.minute)}';

/// Aceita `AAAA-MM-DD` (meia-noite) ou `AAAA-MM-DDTHH:mm[:ss]`.
DateTime fromIsoDateTime(String s) {
  final date = fromIsoDate(s);
  if (s.length < 16) return date;
  final h = int.parse(s.substring(11, 13));
  final m = int.parse(s.substring(14, 16));
  return DateTime(date.year, date.month, date.day, h, m);
}

/// Minutos desde a meia-noite → `HH:mm`.
String minutesToHm(int minutes) => '${_two(minutes ~/ 60)}:${_two(minutes % 60)}';

/// `HH:mm` → minutos desde a meia-noite (null se inválido).
int? hmToMinutes(String? s) {
  if (s == null) return null;
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(s.trim());
  if (m == null) return null;
  final h = int.parse(m.group(1)!);
  final min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return h * 60 + min;
}

/// Data + minutos do dia.
DateTime atMinutes(DateTime day, int minutes) => DateTime(day.year, day.month, day.day, minutes ~/ 60, minutes % 60);

int minutesOfDay(DateTime d) => d.hour * 60 + d.minute;

/// Soma dias de calendário (seguro em mudanças de horário de verão).
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days, d.hour, d.minute);

bool isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Diferença em dias de calendário (b − a).
int daysBetween(DateTime a, DateTime b) =>
    DateTime.utc(b.year, b.month, b.day).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// Início da semana que contém [d] (segunda ou domingo).
DateTime startOfWeek(DateTime d, {bool mondayFirst = true}) {
  final day = dateOnly(d);
  final offset = mondayFirst ? day.weekday - 1 : day.weekday % 7;
  return addDays(day, -offset);
}

DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

DateTime endOfMonth(DateTime d) => DateTime(d.year, d.month + 1, 0);

/// Próxima [weekday] (1 = segunda) estritamente depois de [from].
DateTime nextWeekday(DateTime from, int weekday) {
  var diff = (weekday - from.weekday) % 7;
  if (diff == 0) diff = 7;
  return addDays(dateOnly(from), diff);
}

/// Nomes curtos dos dias (1 = segunda).
const weekdayShort = ['', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
const weekdayLong = ['', 'segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
const monthShort = ['', 'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];

/// `dd/mm`
String dayMonth(DateTime d) => '${_two(d.day)}/${_two(d.month)}';

/// `dd/mm/aaaa`
String dayMonthYear(DateTime d) => '${dayMonth(d)}/${d.year}';

String hm(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
