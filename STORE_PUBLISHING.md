# Guia de Publicação — App Store & Google Play

Este checklist cobre tudo que precisa existir **fora do código** para o Salabim
ir ao ar nas duas lojas. Itens marcados 🔒 exigem uma conta/contrato que só
você pode criar (não posso criar contas ou aceitar termos em seu nome).

## 1. Contas obrigatórias

| Conta | Custo | Link |
|---|---|---|
| 🔒 Apple Developer Program | US$99/ano | https://developer.apple.com/programs/enroll/ |
| 🔒 Google Play Console | US$25 (pagamento único) | https://play.google.com/console/signup |
| 🔒 Conta de pessoa jurídica ou física com CPF/CNPJ para faturamento nas duas lojas | — | — |

## 2. Identidade do app

- **Nome:** Salabim
- **Bundle ID / Application ID sugerido:** `com.salabim.app` (defina antes de gerar
  `android/` e `ios/` com `flutter create`, veja `mobile/README.md` — trocar depois
  é trabalhoso)
- **Ícone:** 1024×1024px, sem transparência, sem cantos arredondados (a loja
  arredonda automaticamente)
- **Splash screen:** gerar com `flutter_native_splash` depois que a identidade
  visual final estiver pronta

## 3. Assets obrigatórios de listagem

- Screenshots — no mínimo para os tamanhos de tela mais usados:
  - iOS: iPhone 6.7" (1290×2796) e iPad 12.9" se suportar tablet
  - Android: telefone (mín. 2 imagens) + opcional tablet/Wear
- Descrição curta (Play: 80 caracteres) e longa (até 4000 caracteres)
- Vídeo de preview (opcional, mas aumenta conversão)
- **Categoria sugerida:** Música (iOS: "Music"; Play: "Music & Audio")

## 4. Privacidade — obrigatório nas duas lojas

O Salabim grava áudio do microfone, então isso precisa estar impecável:

- 🔒 **Política de privacidade publicada em uma URL pública** (ex: `salabim.app/privacy`)
  explicando: que o áudio gravado é enviado a provedores terceiros (AudD,
  ACRCloud) só para identificação, não é armazenado permanentemente, e quais
  dados de conta/histórico são guardados.
- **Apple — "App Privacy" (nutrition label) no App Store Connect:** declarar
  coleta de "Audio Data" (uso: App Functionality, não vinculado à identidade
  se você não linkar ao user, ou vinculado se guardar histórico por conta).
- **Google Play — "Data safety" form:** mesma lógica, declarar coleta de áudio
  e finalidade.
- **Justificativa de permissão de microfone**, obrigatória em ambas: texto
  claro tipo *"O Salabim usa o microfone para identificar a música que está
  tocando ou que você está cantarolando."* (já configurado em
  `mobile/README.md` passo 4, `NSMicrophoneUsageDescription`).

## 5. Direitos autorais e conformidade de conteúdo

- O app **não hospeda nem distribui músicas** — apenas identifica e linka para
  plataformas oficiais (Spotify, Apple Music, Deezer, Tidal, YouTube Music).
  Isso é essencial para não cair em revisão de conteúdo pirateado.
- Previews de áudio devem vir **sempre** da URL oficial retornada pelo
  provedor (iTunes/Apple preview, etc.) — nunca de um recorte gravado por
  vocês. O scaffold já segue essa regra (`Track.preview_url` só é preenchido
  com URLs vindas do AudD/plataforma).
- Guarde os Termos de Uso do AudD, ACRCloud, Odesli e Musixmatch — a Apple
  frequentemente pede prova de que você tem permissão para usar dados de
  reconhecimento musical de terceiros durante a revisão.

## 6. Contas de serviço técnicas

- 🔒 **Google Play**: crie uma *service account* (Google Cloud IAM) com
  permissão de "Release manager" e baixe o JSON — usado pelo Fastlane
  (`devops/fastlane/Appfile`) para publicar automaticamente.
- 🔒 **App Store Connect API Key**: gere em App Store Connect → Users and
  Access → Integrations — usado pelo Fastlane/CI para builds automatizados sem
  precisar de 2FA manual a cada deploy.
- 🔒 **Keystore Android**: gere com `keytool` (comando abaixo) e **guarde em
  local seguro** — perder o keystore original te impede de atualizar o app
  depois de publicado.

```bash
keytool -genkey -v -keystore salabim-release.keystore -alias salabim -keyalg RSA -keysize 2048 -validity 10000
```

## 7. Revisão da Apple — pontos que costumam travar apps de reconhecimento de áudio

- Deixe claro na descrição e nas telas que é necessário estar perto da fonte
  de som ou cantarolar diretamente — evita rejeição por "funcionalidade
  incompleta" se o revisor testar em silêncio.
- Tenha uma conta de teste pronta se exigir login.
- Não referencie "Shazam" ou "Hum to Search" (Google) como marcas no texto
  público da loja — use apenas para descrever a *categoria* da funcionalidade,
  nunca como se fosse afiliado a essas empresas.

## 8. Monetização (opcional, Fase 3 do roadmap)

- Recomendado: [RevenueCat](https://www.revenuecat.com) para abstrair
  StoreKit (iOS) e Play Billing (Android) com um único SDK/paywall.
- 🔒 Configurar produtos de assinatura em App Store Connect e Play Console
  antes de integrar o SDK.

## 9. Ordem recomendada de execução

1. Registrar as contas 🔒 (seção 1)
2. Definir bundle id definitivo e gerar `android/`/`ios/` (`mobile/README.md`)
3. Contratar AudD + ACRCloud (mínimo viável para o app funcionar de verdade)
4. Publicar política de privacidade
5. Preencher App Privacy / Data Safety
6. Gerar keystore Android + certificados iOS (`fastlane match` recomendado)
7. Build interno (TestFlight / Play Internal Testing) e testar em dispositivo real
8. Submeter para revisão
