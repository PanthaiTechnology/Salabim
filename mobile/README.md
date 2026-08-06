# Salabim — App Mobile (Flutter)

Este diretório contém o código Dart do app (`lib/`). As pastas nativas
`android/` e `ios/` **ainda não existem** neste scaffold porque o Flutter SDK
não está instalado na máquina onde este projeto foi gerado — você precisa
criá-las uma única vez, na sua máquina com Flutter instalado.

## 1. Pré-requisitos

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (canal stable, 3.24+)
- Android Studio (para o SDK/emulador Android) e/ou Xcode (para iOS, exige macOS)
- Rode `flutter doctor` e resolva qualquer pendência antes de continuar

## 2. Gerar as pastas nativas (uma vez só)

A partir desta pasta (`mobile/`):

```bash
flutter create . --project-name salabim --org com.salabim --platforms android,ios
```

Isso preenche `android/` e `ios/` em cima do `lib/` e `pubspec.yaml` que já
existem, sem sobrescrevê-los.

## 3. Instalar dependências

```bash
flutter pub get
```

## 4. Adicionar a permissão de microfone

**`android/app/src/main/AndroidManifest.xml`** — adicione antes de `<application>`:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" />
<uses-permission android:name="android.permission.INTERNET" />
```

**`ios/Runner/Info.plist`** — adicione dentro do `<dict>` principal:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>O Salabim precisa do microfone para identificar a música que está tocando ou que você está cantarolando.</string>
```

## 5. Rodar em desenvolvimento

Com o backend rodando localmente (veja `../backend/README` no README raiz):

```bash
# Emulador Android: 10.0.2.2 já aponta pro localhost do host (default no código)
flutter run

# Para apontar para um backend hospedado:
flutter run --dart-define=API_BASE_URL=https://api.salabim.app
```

## 6. Gerar ícone e splash (antes de publicar)

Ainda não incluídos neste scaffold — quando tiver a identidade visual final
(logo em alta resolução), use os pacotes `flutter_launcher_icons` e
`flutter_native_splash` para gerar automaticamente para todas as resoluções
iOS/Android.

## 7. Estrutura de pastas

```
lib/
  core/            # tema, constantes
  data/
    models/        # Track, PlatformLink, enums de modo
    services/      # ApiClient (HTTP) e AudioRecorderService (mic)
  features/
    listen/        # Tela principal: botão pulsante + toggle Ouvir/Cantarolar
    result/        # Tela de resultado: capa, preview, links de plataformas
    text_search/   # Busca por letra/descrição
    history/       # Histórico do usuário
  state/           # Providers Riverpod
  main.dart
  app.dart         # Rotas (go_router) e shell com bottom nav
```
