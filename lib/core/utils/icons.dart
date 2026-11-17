// Ícones e cores das categorias (o banco guarda o nome do ícone Material e a
// cor em hex).
import 'package:material_ui/material_ui.dart';

const categoryIcons = <String, IconData>{
  'work': Icons.work_outline,
  'school': Icons.school_outlined,
  'home': Icons.home_outlined,
  'person': Icons.person_outline,
  'favorite': Icons.favorite_outline,
  'payments': Icons.payments_outlined,
  'shopping_cart': Icons.shopping_cart_outlined,
  'fitness_center': Icons.fitness_center,
  'restaurant': Icons.restaurant,
  'local_hospital': Icons.local_hospital_outlined,
  'pets': Icons.pets,
  'directions_car': Icons.directions_car_outlined,
  'flight': Icons.flight_outlined,
  'family_restroom': Icons.family_restroom,
  'celebration': Icons.celebration_outlined,
  'book': Icons.menu_book_outlined,
  'code': Icons.code,
  'brush': Icons.brush_outlined,
  'music_note': Icons.music_note_outlined,
  'sports_soccer': Icons.sports_soccer,
  'build': Icons.build_outlined,
  'cleaning_services': Icons.cleaning_services_outlined,
  'local_laundry_service': Icons.local_laundry_service_outlined,
  'spa': Icons.spa_outlined,
  'church': Icons.church_outlined,
  'volunteer_activism': Icons.volunteer_activism_outlined,
  'phone': Icons.phone_outlined,
  'mail': Icons.mail_outline,
  'event': Icons.event_outlined,
  'star': Icons.star_outline,
  'lightbulb': Icons.lightbulb_outline,
  'savings': Icons.savings_outlined,
};

IconData categoryIcon(String? name) => categoryIcons[name] ?? Icons.label_outline;

/// Paleta para escolher a cor da categoria (legível nos dois temas).
const categoryPalette = [
  '#5B8DEF',
  '#A97CF8',
  '#E0A43A',
  '#3FB8A9',
  '#F0637A',
  '#4CB86A',
  '#F08A3C',
  '#4DA3FF',
  '#D96BC9',
  '#8A94A3',
  '#C9A227',
  '#6FA8A0',
];

Color hexColor(String? hex, [Color fallback = const Color(0xFF8A94A3)]) {
  if (hex == null) return fallback;
  final h = hex.replaceFirst('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fallback : Color(v);
}
