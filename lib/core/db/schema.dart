// Schema do banco e migrations versionadas.
//
// Para mudar o schema: crie uma entrada nova em [migrations] com a próxima
// versão e suba [schemaVersion]. Nunca edite uma migration já publicada.
//
// Diferenças em relação à especificação original (justificadas):
// - `tarefa.ordem`: a ordenação manual por arrastar precisa de uma coluna.
// - `notificacao_agendada.titulo` e `.assinatura`: a tela de diagnóstico
//   mostra "o que" vai disparar, e a assinatura (hora + conteúdo + modo)
//   permite reagendar só o que mudou, inclusive o texto do resumo diário.
// - `notificacao_agendada.tipo` aceita também 'backup' (lembrete semanal de
//   backup) e 'teste' ("Testar lembrete em 1 minuto").
import 'package:sqflite/sqflite.dart';

const schemaVersion = 1;

/// Ordem das tabelas respeitando as chaves estrangeiras (pais primeiro).
/// Usada pelo backup para apagar (ordem inversa) e inserir.
const tablesInOrder = [
  'categoria',
  'tag',
  'recorrencia',
  'tarefa',
  'checklist_item',
  'evento',
  'evento_excecao',
  'tarefa_tag',
  'evento_tag',
  'lembrete',
  'modelo_checklist',
  'modelo_checklist_item',
  'filtro_salvo',
  'notificacao_agendada',
  'config',
];

final Map<int, List<String>> migrations = {
  1: [
    '''
CREATE TABLE categoria (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL UNIQUE,
  cor TEXT NOT NULL,
  icone TEXT NOT NULL,
  ordem INTEGER NOT NULL DEFAULT 0,
  ativo INTEGER NOT NULL DEFAULT 1
)''',
    '''
CREATE TABLE tag (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL UNIQUE,
  cor TEXT
)''',
    '''
CREATE TABLE recorrencia (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  freq TEXT NOT NULL CHECK (freq IN ('diaria','semanal','mensal','anual')),
  intervalo INTEGER NOT NULL DEFAULT 1,
  dias_semana TEXT,
  modo_mensal TEXT CHECK (modo_mensal IN ('dia_do_mes','dia_da_semana')),
  ate TEXT,
  contagem INTEGER
)''',
    '''
CREATE TABLE tarefa (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  titulo TEXT NOT NULL,
  descricao TEXT,
  categoria_id INTEGER REFERENCES categoria(id),
  prioridade INTEGER NOT NULL DEFAULT 4 CHECK (prioridade BETWEEN 1 AND 4),
  data_prazo TEXT,
  hora_prazo TEXT,
  status TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','concluida','cancelada')),
  concluida_em TEXT,
  criada_em TEXT NOT NULL,
  atualizada_em TEXT NOT NULL,
  adiamentos INTEGER NOT NULL DEFAULT 0,
  estimativa_min INTEGER,
  recorrencia_id INTEGER REFERENCES recorrencia(id) ON DELETE SET NULL,
  fixada_hoje INTEGER NOT NULL DEFAULT 0,
  busca TEXT NOT NULL DEFAULT '',
  ordem INTEGER NOT NULL DEFAULT 0,
  CHECK (hora_prazo IS NULL OR data_prazo IS NOT NULL)
)''',
    '''
CREATE TABLE checklist_item (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  tarefa_id INTEGER NOT NULL REFERENCES tarefa(id) ON DELETE CASCADE,
  texto TEXT NOT NULL,
  quantidade TEXT,
  marcado INTEGER NOT NULL DEFAULT 0,
  ordem INTEGER NOT NULL DEFAULT 0
)''',
    '''
CREATE TABLE evento (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  titulo TEXT NOT NULL,
  descricao TEXT,
  local TEXT,
  categoria_id INTEGER REFERENCES categoria(id),
  inicio TEXT NOT NULL,
  fim TEXT NOT NULL,
  dia_inteiro INTEGER NOT NULL DEFAULT 0,
  recorrencia_id INTEGER REFERENCES recorrencia(id) ON DELETE SET NULL,
  criado_em TEXT NOT NULL,
  atualizado_em TEXT NOT NULL,
  busca TEXT NOT NULL DEFAULT ''
)''',
    '''
CREATE TABLE evento_excecao (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  evento_id INTEGER NOT NULL REFERENCES evento(id) ON DELETE CASCADE,
  data_ocorrencia TEXT NOT NULL,
  cancelada INTEGER NOT NULL DEFAULT 0,
  novo_inicio TEXT,
  novo_fim TEXT,
  novo_titulo TEXT,
  UNIQUE (evento_id, data_ocorrencia)
)''',
    '''
CREATE TABLE tarefa_tag (
  tarefa_id INTEGER NOT NULL REFERENCES tarefa(id) ON DELETE CASCADE,
  tag_id INTEGER NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
  PRIMARY KEY (tarefa_id, tag_id)
)''',
    '''
CREATE TABLE evento_tag (
  evento_id INTEGER NOT NULL REFERENCES evento(id) ON DELETE CASCADE,
  tag_id INTEGER NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
  PRIMARY KEY (evento_id, tag_id)
)''',
    '''
CREATE TABLE lembrete (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  alvo_tipo TEXT NOT NULL CHECK (alvo_tipo IN ('tarefa','evento')),
  alvo_id INTEGER NOT NULL,
  antecedencia_min INTEGER,
  data_hora TEXT,
  CHECK ((antecedencia_min IS NULL) <> (data_hora IS NULL))
)''',
    '''
CREATE TABLE modelo_checklist (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL UNIQUE
)''',
    '''
CREATE TABLE modelo_checklist_item (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  modelo_id INTEGER NOT NULL REFERENCES modelo_checklist(id) ON DELETE CASCADE,
  texto TEXT NOT NULL,
  quantidade TEXT,
  ordem INTEGER NOT NULL DEFAULT 0
)''',
    '''
CREATE TABLE filtro_salvo (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  nome TEXT NOT NULL UNIQUE,
  json TEXT NOT NULL
)''',
    '''
CREATE TABLE notificacao_agendada (
  notification_id INTEGER PRIMARY KEY,
  tipo TEXT NOT NULL CHECK (tipo IN ('lembrete','resumo','backup','teste')),
  alvo_tipo TEXT,
  alvo_id INTEGER,
  ocorrencia TEXT,
  dispara_em TEXT NOT NULL,
  titulo TEXT,
  assinatura TEXT
)''',
    '''
CREATE TABLE config (
  chave TEXT PRIMARY KEY,
  valor TEXT NOT NULL
)''',
    'CREATE INDEX idx_tarefa_status_prazo ON tarefa(status, data_prazo)',
    'CREATE INDEX idx_tarefa_categoria ON tarefa(categoria_id)',
    'CREATE INDEX idx_evento_inicio ON evento(inicio)',
    'CREATE INDEX idx_lembrete_alvo ON lembrete(alvo_tipo, alvo_id)',
    'CREATE INDEX idx_checklist_tarefa ON checklist_item(tarefa_id)',
  ],
};

/// Categorias iniciais: cores distintas, legíveis no claro e no escuro.
const seedCategories = [
  ('Trabalho', '#5B8DEF', 'work'),
  ('Estudo', '#A97CF8', 'school'),
  ('Casa', '#E0A43A', 'home'),
  ('Pessoal', '#3FB8A9', 'person'),
  ('Saúde', '#F0637A', 'favorite'),
  ('Finanças', '#4CB86A', 'payments'),
  ('Compras', '#F08A3C', 'shopping_cart'),
];

const seedMarketItems = [
  'arroz',
  'feijão',
  'óleo',
  'açúcar',
  'café',
  'leite',
  'ovos',
  'pão',
  'sal',
  'papel higiênico',
  'detergente',
];

const seedConfig = {
  'resumo_ativo': '1',
  'resumo_hora': '07:00',
  'inicio_semana': 'segunda',
  'lembrete_padrao_evento_min': '15',
  'lembrete_padrao_tarefa_hora': '09:00',
  'adiar_padrao_min': '60',
  'tema': 'sistema',
  'pin_ativo': '0',
  // Extras do app (fora da tabela da especificação).
  'onboarding_concluido': '0',
  'mostrar_tarefas_calendario': '1',
  'backup_semanal': '0',
};

Future<void> seedV1(DatabaseExecutor db) async {
  for (final (i, (name, color, icon)) in seedCategories.indexed) {
    await db.insert('categoria', {'nome': name, 'cor': color, 'icone': icon, 'ordem': i, 'ativo': 1});
  }
  final modelo = await db.insert('modelo_checklist', {'nome': 'Mercado'});
  for (final (i, item) in seedMarketItems.indexed) {
    await db.insert('modelo_checklist_item', {'modelo_id': modelo, 'texto': item, 'ordem': i});
  }
  for (final e in seedConfig.entries) {
    await db.insert('config', {'chave': e.key, 'valor': e.value});
  }
}

Future<void> migrate(DatabaseExecutor db, int from, int to) async {
  for (var v = from + 1; v <= to; v++) {
    for (final sql in migrations[v] ?? const <String>[]) {
      await db.execute(sql);
    }
    if (v == 1) await seedV1(db);
  }
}
