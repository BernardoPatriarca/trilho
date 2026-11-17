// Modelos do domínio (imutáveis) e conversão de/para linhas do SQLite.
import 'dates.dart';

enum TaskStatus {
  pendente,
  concluida,
  cancelada;

  static TaskStatus parse(String s) => TaskStatus.values.firstWhere((v) => v.name == s, orElse: () => pendente);

  String get label => switch (this) {
    pendente => 'Pendente',
    concluida => 'Concluída',
    cancelada => 'Cancelada',
  };
}

enum TargetType {
  tarefa,
  evento;

  static TargetType parse(String s) => s == 'evento' ? evento : tarefa;
}

class Category {
  const Category({
    this.id,
    required this.name,
    required this.color,
    required this.icon,
    this.order = 0,
    this.active = true,
  });

  final int? id;
  final String name;

  /// Hex `#RRGGBB`.
  final String color;

  /// Nome do ícone Material (ex.: `shopping_cart`).
  final String icon;
  final int order;
  final bool active;

  factory Category.fromRow(Map<String, Object?> r) => Category(
    id: r['id'] as int,
    name: r['nome'] as String,
    color: r['cor'] as String,
    icon: r['icone'] as String,
    order: r['ordem'] as int,
    active: (r['ativo'] as int) == 1,
  );

  Map<String, Object?> toRow() => {'nome': name, 'cor': color, 'icone': icon, 'ordem': order, 'ativo': active ? 1 : 0};

  Category copyWith({String? name, String? color, String? icon, int? order, bool? active}) => Category(
    id: id,
    name: name ?? this.name,
    color: color ?? this.color,
    icon: icon ?? this.icon,
    order: order ?? this.order,
    active: active ?? this.active,
  );
}

class Tag {
  const Tag({this.id, required this.name, this.color});
  final int? id;
  final String name;
  final String? color;

  factory Tag.fromRow(Map<String, Object?> r) =>
      Tag(id: r['id'] as int, name: r['nome'] as String, color: r['cor'] as String?);
}

enum Freq {
  diaria,
  semanal,
  mensal,
  anual;

  static Freq parse(String s) => Freq.values.firstWhere((f) => f.name == s);

  String get label => switch (this) {
    diaria => 'Diária',
    semanal => 'Semanal',
    mensal => 'Mensal',
    anual => 'Anual',
  };
}

enum MonthlyMode {
  /// "todo dia 10"
  diaDoMes('dia_do_mes'),

  /// "toda 2ª terça"
  diaDaSemana('dia_da_semana');

  const MonthlyMode(this.db);
  final String db;

  static MonthlyMode? parse(String? s) => s == null ? null : MonthlyMode.values.firstWhere((m) => m.db == s);
}

/// Regra de recorrência (tabela `recorrencia`).
class RecurrenceRule {
  const RecurrenceRule({
    this.id,
    required this.freq,
    this.interval = 1,
    this.weekdays = const [],
    this.monthlyMode,
    this.until,
    this.count,
  });

  final int? id;
  final Freq freq;

  /// A cada N períodos (>= 1).
  final int interval;

  /// Dias da semana (1 = segunda ... 7 = domingo), para `semanal`.
  final List<int> weekdays;
  final MonthlyMode? monthlyMode;

  /// Última data possível (inclusiva).
  final DateTime? until;

  /// Número máximo de ocorrências.
  final int? count;

  factory RecurrenceRule.fromRow(Map<String, Object?> r) => RecurrenceRule(
    id: r['id'] as int,
    freq: Freq.parse(r['freq'] as String),
    interval: r['intervalo'] as int,
    weekdays: ((r['dias_semana'] as String?) ?? '').split(',').where((s) => s.isNotEmpty).map(int.parse).toList(),
    monthlyMode: MonthlyMode.parse(r['modo_mensal'] as String?),
    until: r['ate'] == null ? null : fromIsoDate(r['ate'] as String),
    count: r['contagem'] as int?,
  );

  Map<String, Object?> toRow() => {
    'freq': freq.name,
    'intervalo': interval,
    'dias_semana': weekdays.isEmpty ? null : (weekdays.toList()..sort()).join(','),
    'modo_mensal': freq == Freq.mensal ? (monthlyMode ?? MonthlyMode.diaDoMes).db : null,
    'ate': until == null ? null : toIsoDate(until!),
    'contagem': count,
  };

  RecurrenceRule copyWith({
    int? id,
    Freq? freq,
    int? interval,
    List<int>? weekdays,
    MonthlyMode? monthlyMode,
    DateTime? until,
    bool clearUntil = false,
    int? count,
    bool clearCount = false,
  }) => RecurrenceRule(
    id: id ?? this.id,
    freq: freq ?? this.freq,
    interval: interval ?? this.interval,
    weekdays: weekdays ?? this.weekdays,
    monthlyMode: monthlyMode ?? this.monthlyMode,
    until: clearUntil ? null : (until ?? this.until),
    count: clearCount ? null : (count ?? this.count),
  );

  RecurrenceRule withoutId() => RecurrenceRule(
    freq: freq,
    interval: interval,
    weekdays: weekdays,
    monthlyMode: monthlyMode,
    until: until,
    count: count,
  );
}

class Task {
  const Task({
    this.id,
    required this.title,
    this.description,
    this.categoryId,
    this.priority = 4,
    this.dueDate,
    this.dueMinutes,
    this.status = TaskStatus.pendente,
    this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    this.postponements = 0,
    this.estimateMin,
    this.recurrenceId,
    this.pinnedToday = false,
    this.order = 0,
  });

  final int? id;
  final String title;
  final String? description;
  final int? categoryId;

  /// 1 (Urgente) a 4 (Baixa).
  final int priority;

  /// Só a data do prazo (meia-noite).
  final DateTime? dueDate;

  /// Hora do prazo em minutos desde a meia-noite (exige [dueDate]).
  final int? dueMinutes;
  final TaskStatus status;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Quantas vezes o prazo foi empurrado para frente.
  final int postponements;
  final int? estimateMin;
  final int? recurrenceId;

  /// "Fazer hoje" sem mudar o prazo.
  final bool pinnedToday;

  /// Ordem manual (arrastar na lista).
  final int order;

  bool get isPending => status == TaskStatus.pendente;
  bool get isDone => status == TaskStatus.concluida;
  bool get hasTime => dueDate != null && dueMinutes != null;
  bool get isRecurring => recurrenceId != null;

  /// Prazo com hora (ou meia-noite se só data).
  DateTime? get dueDateTime => dueDate == null ? null : atMinutes(dueDate!, dueMinutes ?? 0);

  factory Task.fromRow(Map<String, Object?> r) => Task(
    id: r['id'] as int,
    title: r['titulo'] as String,
    description: r['descricao'] as String?,
    categoryId: r['categoria_id'] as int?,
    priority: r['prioridade'] as int,
    dueDate: r['data_prazo'] == null ? null : fromIsoDate(r['data_prazo'] as String),
    dueMinutes: hmToMinutes(r['hora_prazo'] as String?),
    status: TaskStatus.parse(r['status'] as String),
    completedAt: r['concluida_em'] == null ? null : fromIsoDateTime(r['concluida_em'] as String),
    createdAt: fromIsoDateTime(r['criada_em'] as String),
    updatedAt: fromIsoDateTime(r['atualizada_em'] as String),
    postponements: r['adiamentos'] as int,
    estimateMin: r['estimativa_min'] as int?,
    recurrenceId: r['recorrencia_id'] as int?,
    pinnedToday: (r['fixada_hoje'] as int) == 1,
    order: (r['ordem'] as int?) ?? 0,
  );

  /// Linha sem `id` e sem `busca` (o repositório calcula a busca).
  Map<String, Object?> toRow() => {
    'titulo': title,
    'descricao': description,
    'categoria_id': categoryId,
    'prioridade': priority,
    'data_prazo': dueDate == null ? null : toIsoDate(dueDate!),
    'hora_prazo': dueDate == null || dueMinutes == null ? null : minutesToHm(dueMinutes!),
    'status': status.name,
    'concluida_em': completedAt == null ? null : toIsoDateTime(completedAt!),
    'criada_em': toIsoDateTime(createdAt),
    'atualizada_em': toIsoDateTime(updatedAt),
    'adiamentos': postponements,
    'estimativa_min': estimateMin,
    'recorrencia_id': recurrenceId,
    'fixada_hoje': pinnedToday ? 1 : 0,
    'ordem': order,
  };

  Task copyWith({
    int? id,
    String? title,
    String? description,
    bool clearDescription = false,
    int? categoryId,
    bool clearCategory = false,
    int? priority,
    DateTime? dueDate,
    bool clearDue = false,
    int? dueMinutes,
    bool clearTime = false,
    TaskStatus? status,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? postponements,
    int? estimateMin,
    bool clearEstimate = false,
    int? recurrenceId,
    bool clearRecurrence = false,
    bool? pinnedToday,
    int? order,
  }) => Task(
    id: id ?? this.id,
    title: title ?? this.title,
    description: clearDescription ? null : (description ?? this.description),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    priority: priority ?? this.priority,
    dueDate: clearDue ? null : (dueDate ?? this.dueDate),
    dueMinutes: clearDue || clearTime ? null : (dueMinutes ?? this.dueMinutes),
    status: status ?? this.status,
    completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    postponements: postponements ?? this.postponements,
    estimateMin: clearEstimate ? null : (estimateMin ?? this.estimateMin),
    recurrenceId: clearRecurrence ? null : (recurrenceId ?? this.recurrenceId),
    pinnedToday: pinnedToday ?? this.pinnedToday,
    order: order ?? this.order,
  );
}

class ChecklistItem {
  const ChecklistItem({this.id, this.taskId, required this.text, this.quantity, this.checked = false, this.order = 0});

  final int? id;
  final int? taskId;
  final String text;

  /// Livre: '2', '1 kg', '3 un'.
  final String? quantity;
  final bool checked;
  final int order;

  factory ChecklistItem.fromRow(Map<String, Object?> r) => ChecklistItem(
    id: r['id'] as int,
    taskId: r['tarefa_id'] as int,
    text: r['texto'] as String,
    quantity: r['quantidade'] as String?,
    checked: (r['marcado'] as int) == 1,
    order: r['ordem'] as int,
  );

  ChecklistItem copyWith({
    int? id,
    bool clearId = false,
    int? taskId,
    String? text,
    String? quantity,
    bool clearQuantity = false,
    bool? checked,
    int? order,
  }) => ChecklistItem(
    id: clearId ? null : (id ?? this.id),
    taskId: taskId ?? this.taskId,
    text: text ?? this.text,
    quantity: clearQuantity ? null : (quantity ?? this.quantity),
    checked: checked ?? this.checked,
    order: order ?? this.order,
  );
}

/// Progresso da checklist: `marcados/total`.
class ChecklistProgress {
  const ChecklistProgress(this.checked, this.total);
  final int checked;
  final int total;

  static const empty = ChecklistProgress(0, 0);

  bool get isEmpty => total == 0;
  bool get allChecked => total > 0 && checked == total;
  double get fraction => total == 0 ? 0 : checked / total;
  String get label => '$checked/$total';

  factory ChecklistProgress.of(Iterable<ChecklistItem> items) {
    var c = 0, t = 0;
    for (final i in items) {
      t++;
      if (i.checked) c++;
    }
    return ChecklistProgress(c, t);
  }
}

class Event {
  const Event({
    this.id,
    required this.title,
    this.description,
    this.location,
    this.categoryId,
    required this.start,
    required this.end,
    this.allDay = false,
    this.recurrenceId,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String title;
  final String? description;
  final String? location;
  final int? categoryId;

  /// Início. Em evento de dia inteiro, só a data.
  final DateTime start;

  /// Fim. Em evento de dia inteiro, o último dia (inclusivo).
  final DateTime end;
  final bool allDay;
  final int? recurrenceId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isRecurring => recurrenceId != null;

  /// Duração (dia inteiro: dias de calendário − 1, em `Duration`).
  Duration get duration => allDay ? Duration(days: daysBetween(start, end)) : end.difference(start);

  factory Event.fromRow(Map<String, Object?> r) {
    final allDay = (r['dia_inteiro'] as int) == 1;
    return Event(
      id: r['id'] as int,
      title: r['titulo'] as String,
      description: r['descricao'] as String?,
      location: r['local'] as String?,
      categoryId: r['categoria_id'] as int?,
      start: fromIsoDateTime(r['inicio'] as String),
      end: fromIsoDateTime(r['fim'] as String),
      allDay: allDay,
      recurrenceId: r['recorrencia_id'] as int?,
      createdAt: fromIsoDateTime(r['criado_em'] as String),
      updatedAt: fromIsoDateTime(r['atualizado_em'] as String),
    );
  }

  Map<String, Object?> toRow() => {
    'titulo': title,
    'descricao': description,
    'local': location,
    'categoria_id': categoryId,
    'inicio': allDay ? toIsoDate(start) : toIsoDateTime(start),
    'fim': allDay ? toIsoDate(end) : toIsoDateTime(end),
    'dia_inteiro': allDay ? 1 : 0,
    'recorrencia_id': recurrenceId,
    'criado_em': toIsoDateTime(createdAt),
    'atualizado_em': toIsoDateTime(updatedAt),
  };

  Event copyWith({
    int? id,
    String? title,
    String? description,
    bool clearDescription = false,
    String? location,
    bool clearLocation = false,
    int? categoryId,
    bool clearCategory = false,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    int? recurrenceId,
    bool clearRecurrence = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Event(
    id: id ?? this.id,
    title: title ?? this.title,
    description: clearDescription ? null : (description ?? this.description),
    location: clearLocation ? null : (location ?? this.location),
    categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
    start: start ?? this.start,
    end: end ?? this.end,
    allDay: allDay ?? this.allDay,
    recurrenceId: clearRecurrence ? null : (recurrenceId ?? this.recurrenceId),
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}

/// Exceção de uma ocorrência ("só este evento").
class EventException {
  const EventException({
    this.id,
    required this.eventId,
    required this.occurrenceDate,
    this.cancelled = false,
    this.newStart,
    this.newEnd,
    this.newTitle,
  });

  final int? id;
  final int eventId;

  /// Data original da ocorrência.
  final DateTime occurrenceDate;
  final bool cancelled;
  final DateTime? newStart;
  final DateTime? newEnd;
  final String? newTitle;

  factory EventException.fromRow(Map<String, Object?> r) => EventException(
    id: r['id'] as int,
    eventId: r['evento_id'] as int,
    occurrenceDate: fromIsoDate(r['data_ocorrencia'] as String),
    cancelled: (r['cancelada'] as int) == 1,
    newStart: r['novo_inicio'] == null ? null : fromIsoDateTime(r['novo_inicio'] as String),
    newEnd: r['novo_fim'] == null ? null : fromIsoDateTime(r['novo_fim'] as String),
    newTitle: r['novo_titulo'] as String?,
  );

  Map<String, Object?> toRow({required bool allDay}) {
    String? f(DateTime? d) => d == null ? null : (allDay ? toIsoDate(d) : toIsoDateTime(d));
    return {
      'evento_id': eventId,
      'data_ocorrencia': toIsoDate(occurrenceDate),
      'cancelada': cancelled ? 1 : 0,
      'novo_inicio': f(newStart),
      'novo_fim': f(newEnd),
      'novo_titulo': newTitle,
    };
  }
}

/// Lembrete: relativo (minutos antes do início/prazo) OU absoluto.
class Reminder {
  const Reminder({this.id, required this.targetType, this.targetId, this.offsetMin, this.at})
    : assert((offsetMin == null) != (at == null));

  const Reminder.relative(int minutesBefore, {this.id, this.targetType = TargetType.tarefa, this.targetId})
    : offsetMin = minutesBefore,
      at = null;

  const Reminder.absolute(DateTime this.at, {this.id, this.targetType = TargetType.tarefa, this.targetId})
    : offsetMin = null;

  final int? id;
  final TargetType targetType;
  final int? targetId;
  final int? offsetMin;
  final DateTime? at;

  bool get isRelative => offsetMin != null;

  factory Reminder.fromRow(Map<String, Object?> r) => Reminder(
    id: r['id'] as int,
    targetType: TargetType.parse(r['alvo_tipo'] as String),
    targetId: r['alvo_id'] as int,
    offsetMin: r['antecedencia_min'] as int?,
    at: r['data_hora'] == null ? null : fromIsoDateTime(r['data_hora'] as String),
  );

  Map<String, Object?> toRow(TargetType type, int targetId) => {
    'alvo_tipo': type.name,
    'alvo_id': targetId,
    'antecedencia_min': offsetMin,
    'data_hora': at == null ? null : toIsoDateTime(at!),
  };

  /// "Na hora", "15 min antes", "1 h antes", "1 dia antes", "17/11 09:00".
  String get label {
    if (at != null) return '${dayMonth(at!)} às ${hm(at!)}';
    final m = offsetMin!;
    if (m == 0) return 'Na hora';
    if (m % 1440 == 0) return '${plural0(m ~/ 1440, 'dia')} antes';
    if (m % 60 == 0) return '${m ~/ 60} h antes';
    return '$m min antes';
  }

  /// Mesmo lembrete (ignora id e alvo).
  bool sameAs(Reminder o) => o.offsetMin == offsetMin && o.at == at;
}

String plural0(int n, String s) => '$n ${n == 1 ? s : '${s}s'}';

class ChecklistTemplate {
  const ChecklistTemplate({this.id, required this.name, this.items = const []});
  final int? id;
  final String name;
  final List<ChecklistItem> items;
}

/// Uma ocorrência concreta de evento (já com exceções aplicadas).
class EventOccurrence {
  const EventOccurrence({
    required this.event,
    required this.start,
    required this.end,
    required this.occurrenceDate,
    required this.title,
    this.modified = false,
  });

  final Event event;
  final DateTime start;
  final DateTime end;

  /// Data original na série (chave das exceções).
  final DateTime occurrenceDate;
  final String title;

  /// Alterada por uma exceção "só este evento".
  final bool modified;

  bool get allDay => event.allDay;
  int? get categoryId => event.categoryId;

  /// O evento ocupa algum momento do dia [day]?
  bool occursOn(DateTime day) {
    final d = dateOnly(day);
    if (allDay) {
      return !d.isBefore(dateOnly(start)) && !d.isAfter(dateOnly(end));
    }
    final dayEnd = addDays(d, 1);
    return start.isBefore(dayEnd) && end.isAfter(d) || (start == end && isSameDay(start, d));
  }
}
