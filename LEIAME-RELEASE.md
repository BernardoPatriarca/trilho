# Release do Trilho: chave, APK e instalação

## 1. Chave de release (keystore)

O Android só instala uma **atualização** por cima do app se ela vier assinada
com a **mesma chave**. Perdeu a chave = precisa desinstalar (e perder os dados,
a não ser que você tenha um backup JSON). Então: gere uma vez e guarde bem.

No Ubuntu, **fora do repositório**:

```bash
mkdir -p ~/chaves
keytool -genkeypair -v \
  -keystore ~/chaves/trilho-release.jks \
  -storetype PKCS12 \
  -alias trilho \
  -keyalg RSA -keysize 2048 \
  -validity 10000
```

- `-keystore`: arquivo da chave. Guarde uma cópia num lugar seguro (pendrive,
  gerenciador de senhas). **Nunca** commite.
- `-alias`: nome da chave dentro do arquivo.
- `-validity 10000`: ~27 anos.
- O `keytool` pede uma senha e seus dados (nome etc.). Anote a senha.

Depois crie `android/key.properties` (já está no `.gitignore`):

```properties
storeFile=/home/SEU_USUARIO/chaves/trilho-release.jks
storePassword=SUA_SENHA
keyAlias=trilho
keyPassword=SUA_SENHA
```

O que **não** commitar: `android/key.properties`, qualquer `*.jks` ou
`*.keystore` de release. O `.gitignore` já bloqueia esses arquivos.

### A chave de teste versionada

Enquanto `android/key.properties` não existir, o Gradle assina com
`android/app/trilho-teste.keystore` (senha `trilho-teste`). Ela está no git de
propósito e **não é segredo**: serve só para que todo APK gerado pelo GitHub
Actions tenha a mesma assinatura e uma versão nova instale por cima da
anterior durante os testes.

Quando você passar a usar a sua chave de release, o Android vai recusar a
atualização por cima do APK de teste (assinaturas diferentes). Faça assim uma
única vez: **Mais › Backup e exportação › Exportar backup**, desinstale,
instale o APK novo e **Importar backup**.

### Usar a sua chave no GitHub Actions (opcional)

Em *Settings › Secrets and variables › Actions* do repositório, crie:

| Secret | Valor |
|---|---|
| `TRILHO_KEYSTORE_BASE64` | saída de `base64 -w0 ~/chaves/trilho-release.jks` |
| `TRILHO_KEYSTORE_PASSWORD` | senha do keystore |
| `TRILHO_KEY_ALIAS` | `trilho` |
| `TRILHO_KEY_PASSWORD` | senha da chave |

Com os quatro definidos, o workflow assina com a sua chave; sem eles, usa a de
teste.

## 2. Gerar o APK

```bash
flutter build apk --release                 # universal (todas as arquiteturas)
flutter build apk --release --split-per-abi # menores, um por arquitetura
```

Saída em `build/app/outputs/flutter-apk/`:

- `app-release.apk` — universal, funciona em qualquer celular;
- `app-arm64-v8a-release.apk` — celulares atuais (64 bits). **Use este** se
  quiser o menor arquivo;
- `app-armeabi-v7a-release.apk` — celulares antigos de 32 bits;
- `app-x86_64-release.apk` — emuladores.

O workflow `.github/workflows/apk.yml` faz isso a cada push: roda
`flutter analyze` e `flutter test`, gera os APKs, **confere que não há
permissão `INTERNET`** e publica tudo numa *release* (pré-lançamento) do
repositório.

### Conferir as permissões à mão

```bash
$ANDROID_HOME/build-tools/<versão>/aapt2 dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

Não deve aparecer `android.permission.INTERNET`.

## 3. Instalar no celular

**Pelo arquivo (mais simples):** baixe o APK no celular (pela página de
releases do GitHub ou copiando pelo cabo/Drive), toque nele e permita
"instalar apps desconhecidos" para o navegador ou gerenciador de arquivos
quando o Android pedir.

**Por USB com adb:** ative *Opções do desenvolvedor › Depuração USB* e:

```bash
adb devices                                   # o celular precisa aparecer
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

O `-r` reinstala mantendo os dados (mesma chave).

## 4. Nova versão

Suba a versão no `pubspec.yaml` a cada APK novo (`1.0.0+1` → `1.0.1+2`): o
número depois do `+` (versionCode) precisa sempre aumentar para o Android
aceitar a atualização.

## 5. Checklist do release (seção 12 da especificação)

- [x] Chave de release: comando `keytool` acima; `android/key.properties` e
      `*.jks` no `.gitignore`.
- [x] `signingConfig` de release lendo `android/key.properties` (sem ele,
      chave de teste).
- [x] R8 ligado (`isMinifyEnabled` + `isShrinkResources`) com regras de
      `keep` do plugin de notificações em `android/app/proguard-rules.pro`
      e o ícone da notificação protegido em `res/raw/keep.xml`.
- [x] `flutter build apk --release` e `--split-per-abi` (o workflow gera os
      dois e lista o tamanho de cada arquivo no resumo da execução).
- [x] Sem permissão `INTERNET` no APK de release (o workflow falha se
      aparecer). Ela existe só nos manifests de `debug`/`profile`, que o
      `flutter run` usa para o hot reload.
- [x] Nome no celular: **Trilho**. Versão inicial `1.0.0+1`.

## 6. Primeiro teste no celular (notificações)

Notificação se comporta diferente no emulador, então teste no aparelho:

1. Abra o app, siga o onboarding e permita notificações.
2. **Mais › Notificações**: tudo verde? Se "Otimização de bateria" estiver
   ativa, toque em **Desativar** (e siga a dica do seu fabricante).
3. Toque em **Testar lembrete em 1 minuto**, bloqueie a tela e espere.
4. Crie *"Prender o varão na parede"* com prazo daqui a 2 minutos e espere o
   lembrete com o celular bloqueado. Toque em **Concluir** na própria
   notificação: a tarefa aparece concluída ao abrir o app.
5. Reinicie o celular e confira em **Mais › Notificações › Próximas** que os
   lembretes continuam lá (o plugin reagenda no boot).
