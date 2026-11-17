# Trilho — o caminho que mantém o seu dia no curso

App Android pessoal de **agenda, calendário e tarefas**, irmão do **Lastro**
(finanças) e do **Fôlego** (treino). Eventos com recorrência, tarefas com
prazo, prioridade e checklist, lembretes confiáveis e um resumo do dia às 7h.

- 100% offline e local (SQLite). Sem backend, login, analytics nem permissão
  de internet no APK de release.
- Os dados só saem do celular pelo backup JSON (ou `.ics`) que você exporta.

## Comandos

```bash
flutter pub get
flutter analyze                 # zero erros e avisos
flutter test                    # domínio, repositórios e widgets
flutter run                     # emulador ou celular via USB
flutter build apk --release     # APK universal
flutter build apk --release --split-per-abi   # um APK por arquitetura
```

Cada push para o GitHub roda `.github/workflows/apk.yml`: analisa, testa,
gera os APKs, confere que não há permissão `INTERNET` e publica uma
pré-release com os arquivos. Chave, build e instalação: [LEIAME-RELEASE.md](LEIAME-RELEASE.md).

```bash
dart run flutter_launcher_icons          # regerar ícone
dart run flutter_native_splash:create    # regerar splash
```

## Estrutura

```
lib/
  main.dart
  app/            tema (claro/escuro), rotas, shell com abas e FAB
  core/           banco, providers, formatação, widgets comuns
  features/
    today/        tela Hoje
    calendar/     mês, semana, dia, lista
    events/       criar/editar evento
    tasks/        lista, detalhe, checklist
    quick_add/    adição rápida com linguagem natural
    search/       busca e filtros salvos
    stats/        estatísticas
    categories/   categorias e tags
    templates/    modelos de checklist
    notifications/ agendamento, canais, ações, diagnóstico
    settings/     Mais, configurações, backup, PIN opcional
  domain/         regras puras (sem Flutter), 100% testadas
test/
  domain/   recorrência, parser (42 casos), Hoje, busca, estatísticas, resumo, .ics
  data/     repositórios e agendador de notificações (SQLite em memória + fake do plugin)
  widget/   adição rápida, checklist, concluir com desfazer, onboarding, PIN, telas em 320 dp
```

Camadas: telas → providers (Riverpod) → repositórios → banco. Toda escrita
chama `ref.dataChanged()`: sobe a "revisão" dos dados (as telas recarregam
sozinhas) e reagenda as notificações.

## Decisões de implementação

- **Flutter 3.50 / Material**: o app importa `package:material_ui/material_ui.dart`
  (o Material saiu do SDK nessa versão), como o Fôlego.
- **Tema**: as cores ficam em `TrilhoColors` (`ThemeExtension`), lidas com
  `context.colors`, para as telas funcionarem no claro e no escuro. O texto
  sobre o azul-lavanda é sempre escuro. No claro, erro/aviso/sucesso e links
  usam tons mais escuros para manter o contraste.
- **Prioridade** nunca aparece só pela cor: `PriorityBadge` mostra `P1 · Urgente`.
- **Android**: `minSdk 26`, retrato, desugaring ligado (exigido pelas
  notificações), `allowBackup=false` e assinatura de release lida de
  `android/key.properties`; sem esse arquivo, usa a chave de **teste**
  `android/app/trilho-teste.keystore` (não é segredo; serve para os APKs do
  CI instalarem um por cima do outro).
- **Material antigo no calendário**: o `table_calendar` ainda usa
  `flutter/material.dart`, que no Flutter 3.50 é uma árvore separada do
  `material_ui`. A visão Mês fica dentro de um `Material` dessa biblioteca
  (só ali), senão os toques do cabeçalho quebram.
- **Semana e Dia**: grade de horários própria (`features/calendar/time_grid.dart`)
  em vez de pacote: sobreposição lado a lado, faixa de dia inteiro, tarefas
  com hora como marcadores, linha da hora atual e toque longo para criar.
- **Schema v1**: igual à especificação, mais `tarefa.ordem` (ordem manual),
  `notificacao_agendada.titulo`/`assinatura` (diagnóstico e reagendar só o
  que mudou) e os tipos `backup`/`teste` em `notificacao_agendada.tipo`.
- **Recorrência de tarefa**: cada instância tem a sua cópia da regra; a
  contagem restante cai 1 a cada conclusão. O próximo prazo sai do prazo
  original. Tarefa recorrente exige data.
- **Evento de dia inteiro**: `fim` é o último dia (inclusivo). No `.ics`, o
  `DTEND` vira o dia seguinte, como manda o formato.
- **"Todos" numa ocorrência**: o deslocamento feito naquela ocorrência
  (horário/data) é aplicado à série inteira.
- **Notificações**: `SCHEDULE_EXACT_ALARM` até o Android 12L e
  `USE_EXACT_ALARM` do 13 em diante (app de agenda/lembretes), então o
  horário exato normalmente já vem liberado. Mesmo assim o app confere com
  `canScheduleExactNotifications()` e cai para `inexactAllowWhileIdle`, com
  aviso no diagnóstico. A otimização de bateria usa um canal nativo pequeno
  (`MainActivity.kt`), sem pacote extra.
- **Reagendamento**: ao abrir e voltar ao app, a cada escrita, depois do boot
  (receiver do plugin) e pelas ações da notificação. O Android não roda
  código do app quando uma notificação agendada dispara, então "reagendar
  quando o resumo dispara" virou: os resumos dos próximos 7 dias e os
  lembretes dos próximos 30 ficam sempre prontos, e qualquer abertura do app
  empurra a janela para frente.
- **Lembrete padrão**: entra só em item novo cujo usuário não mexeu nos
  lembretes (tarefa com data: na hora do prazo, ou às 9h se só data;
  evento: 15 min antes). Absolutos andam junto com o prazo na próxima
  instância.
- **Busca**: o texto filtra no SQL (`LIKE` na coluna `busca`); os outros
  filtros, no domínio. Filtros só de tarefa (prioridade, status, prazo,
  checklist) excluem eventos.
- **Adiar pela notificação**: novo prazo = agora + 1 h. "Reagendar tudo para
  hoje" tira a hora das atrasadas cuja hora já passou.
- **PIN**: pedido ao abrir e de novo depois de 2 min em segundo plano; 5
  erros seguidos travam por 30 s. Hash SHA-256 com salt no
  `flutter_secure_storage`; nunca entra no backup.
- **Backup**: todas as tabelas + `schema_version`; a importação é atômica e
  recusa versão mais nova. `notificacao_agendada` vai no arquivo mas não é
  restaurada: depois de importar o app cancela tudo e reagenda.
- **Vibração** ao concluir não é esperada (`unawaited`): em alguns aparelhos
  a chamada demora e segurava a conclusão.
- **Seed de carga** (2.000 eventos) em Mais › Sobre, só no modo debug.

## Fora do MVP (camadas preparadas)

Widget de "Hoje" na tela inicial: `buildToday` (domínio) e
`todayProvider` já entregam tudo pronto. Importação de `.ics`: o formato e a
regra (`RecurrenceRule`/`EventException`) já são os do iCalendar, falta só o
parser de entrada.
