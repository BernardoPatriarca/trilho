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
pré-release com os arquivos.

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
  domain/  data/  widget/
```

Camadas: telas → providers (Riverpod) → repositórios → banco.

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
