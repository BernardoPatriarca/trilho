// Formatação de datas e horas para exibição (pt-BR).
import 'package:intl/intl.dart';

/// "terça-feira, 17 de novembro"
String longDate(DateTime d) {
  final s = DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(d);
  return s[0].toUpperCase() + s.substring(1);
}

/// "17/11/2026"
String shortDate(DateTime d) => DateFormat('dd/MM/yyyy', 'pt_BR').format(d);

/// "14:30"
String hourMinute(DateTime d) => DateFormat('HH:mm', 'pt_BR').format(d);
