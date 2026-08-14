import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../state/app_providers.dart';
import 'widgets/mode_selector.dart';
import 'widgets/pulse_button.dart';

/// Tela principal — o coração do Salabim: um único toque começa a escutar
/// e já busca em tempo real, em segmentos curtos, sem precisar de um
/// segundo toque para "parar e buscar". O resultado aparece assim que
/// qualquer segmento bater. Serve tanto para "ouvir a música tocando"
/// (Shazam) quanto para "cantarolar/assobiar/cantar" (Hum to Search),
/// alternado pelo ModeSelector acima do botão OU deslizando o botão
/// central pra qualquer lado (ver _onDragUpdate/_onDragEnd abaixo).
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> with SingleTickerProviderStateMixin {
  // Duas frases curtas por modo (não mais uma mensagem de duas linhas só —
  // ficava grande demais), alternando a cada "não encontrado": a mesma
  // frase de abertura pros dois modos, e uma segunda frase específica
  // (Ouvir = ambiente/volume, Cantar = afinação/letra). Cada modo mantém
  // sua própria posição na alternância, independente do outro — ver
  // _nextNotFoundMessage. Some sozinha depois de 5s (Future.delayed em
  // ListenController).
  static const _notFoundPhrase1 = 'putzzz, não deu...Foi mau! 🤦💩';
  static const _notFoundPhraseListen2 = 'Aumente o volume ou chegue mais perto do som! 😉';
  static const _notFoundPhraseHum2 = 'Tente cantar mais afinado e mais fiel à letra possível! 😉';

  int _ouvirPhraseIndex = 0;
  int _cantarPhraseIndex = 0;
  String _currentNotFoundMessage = '';

  // Dicas durante a gravação — alternam em loop, sempre nessa ordem (não é
  // aleatório), enquanto grava de verdade em QUALQUER modo (some durante
  // "Processando..."). Cada modo tem seu próprio conjunto de 3 frases, mas
  // o mecanismo (ordem, tempo, fade) é o mesmo pros dois — qualquer ajuste
  // de design daqui pra frente vale pros dois ao mesmo tempo. Substituem
  // tanto o texto de status quanto a dica pequena que existiam antes (duas
  // linhas separadas) por um único texto maior, num só lugar — menos
  // poluição visual, mais fácil de ler.
  static const _cantarRecordingHints = [
    'Cante o mais próximo do microfone possível.',
    'Toque de novo para finalizar a cantoria e buscar.',
    'Ouvindo, buscando....',
  ];
  static const _ouvirRecordingHints = [
    'Aproxime o celular da caixa de som',
    'Toque de novo para cancelar',
    'Ouvindo, buscando....',
  ];
  List<String> _hintPhrasesFor(ListenMode mode) => mode == ListenMode.hum ? _cantarRecordingHints : _ouvirRecordingHints;

  /// Estilo do texto de status fora do loop de dicas (que já tem seu
  /// próprio estilo fixo em 22px). Idle mantém o tamanho original (15px);
  /// "Processando..." e "não encontrado" usam a mesma fonte/opacidade do
  /// loop de dicas, mas no MESMO tamanho maior (22px) — pedido explícito
  /// do usuário, pros dois modos. Erro fica com o estilo de sempre (nunca
  /// foi pedido pra mudar).
  TextStyle _statusTextStyleFor(ListenStatus status) {
    switch (status) {
      case ListenStatus.idle:
        return GoogleFonts.baloo2(
          color: AppColors.textPrimary.withValues(alpha: _hintMaxOpacity),
          fontSize: 15,
          fontWeight: FontWeight.w700,
        );
      case ListenStatus.recording: // só chega aqui durante "Processando..." — isHintCycleActive cobre o resto
      case ListenStatus.notFound:
        return GoogleFonts.baloo2(
          color: AppColors.textPrimary.withValues(alpha: _hintMaxOpacity),
          fontSize: 22,
          fontWeight: FontWeight.w700,
        );
      case ListenStatus.error:
        return const TextStyle(color: AppColors.textSecondary, fontSize: 15);
    }
  }

  // Tempo legível parado (opacidade máxima) antes de começar a sumir.
  static const _hintHoldDuration = Duration(milliseconds: 2200);
  // Duração do fade — usada tanto pro "sumir" quanto pro "aparecer"
  // (são duas animações separadas em sequência, nunca sobrepostas: a
  // pedido explícito, nada de crossfade. Só troca a frase quando a
  // opacidade já chegou em 0 de verdade).
  static const _hintFadeDuration = Duration(milliseconds: 420);
  // Opacidade máxima (quando "visível") abaixo de 1.0 de propósito — a
  // pedido do usuário, fica mais suave/sutil do que letra 100% "chapada".
  // Passou por 0.85 e 0.62 (ainda "muito alta", testado na prática) até
  // fechar em 0.30 — ainda legível porque textPrimary tem bastante
  // contraste com o fundo escuro do app mesmo bem mais transparente.
  static const _hintMaxOpacity = 0.30;

  bool _hintCycleActive = false;
  bool _hintVisible = true;
  int _hintIndex = 0;
  ListenMode _hintMode = ListenMode.listen;
  // Só incrementa a cada start/stop — cada Future.delayed agendado carrega
  // a geração de quando foi criado e confere contra a atual antes de agir.
  // Evita que um fade "fantasma" de um ciclo que já parou (ex: trocou de
  // modo bem rápido) apareça sobreposto ao ciclo novo.
  int _hintCycleGeneration = 0;

  /// Começa (ou reinicia do zero) o loop de dicas pro `mode` — chamado só
  /// na transição real pra "gravando de verdade" (ver ref.listen), nunca
  /// do build, senão reiniciaria a cada rebuild por qualquer outro motivo.
  void _startHintCycle(ListenMode mode) {
    _hintCycleGeneration++;
    _hintCycleActive = true;
    _hintMode = mode;
    _hintIndex = 0;
    _hintVisible = true;
    _scheduleHintFadeOut(_hintCycleGeneration);
  }

  void _stopHintCycle() {
    _hintCycleGeneration++;
    _hintCycleActive = false;
  }

  /// Espera o tempo de leitura e então dispara o fade-out (muda
  /// `_hintVisible` pra false — o AnimatedOpacity na árvore reage sozinho).
  void _scheduleHintFadeOut(int generation) {
    Future.delayed(_hintHoldDuration, () {
      if (!mounted || !_hintCycleActive || generation != _hintCycleGeneration) return;
      setState(() => _hintVisible = false);
    });
  }

  /// Chamado pelo AnimatedOpacity (onEnd) toda vez que uma animação de
  /// opacidade termina — tanto o fim do fade-out quanto o fim do fade-in.
  /// Sequência nunca sobreposta: só troca o texto quando já está 100%
  /// invisível, só volta a esperar quando já está na opacidade máxima de
  /// novo.
  void _onHintFadeEnd() {
    if (!mounted || !_hintCycleActive) return;
    if (!_hintVisible) {
      // Acabou de sumir de vez — troca pra próxima frase (desse modo) e
      // começa a aparecer.
      setState(() {
        _hintIndex = (_hintIndex + 1) % _hintPhrasesFor(_hintMode).length;
        _hintVisible = true;
      });
    } else {
      // Acabou de aparecer de vez — fica um tempo legível e some de novo.
      _scheduleHintFadeOut(_hintCycleGeneration);
    }
  }

  /// Escolhe a próxima frase pra esse modo (alterna 1ª/2ª a cada chamada,
  /// contador independente por modo) e já avança o contador pra próxima
  /// vez. Só deve ser chamado uma vez por transição real pra "não
  /// encontrado" (ver ref.listen), nunca direto de dentro do build.
  String _nextNotFoundMessage(ListenMode mode) {
    if (mode == ListenMode.hum) {
      final message = _cantarPhraseIndex == 0 ? _notFoundPhrase1 : _notFoundPhraseHum2;
      _cantarPhraseIndex = 1 - _cantarPhraseIndex;
      return message;
    }
    final message = _ouvirPhraseIndex == 0 ? _notFoundPhrase1 : _notFoundPhraseListen2;
    _ouvirPhraseIndex = 1 - _ouvirPhraseIndex;
    return message;
  }

  static const _commitThreshold = 50.0;
  // Enquanto grava, "arrastar pra trocar" também cancela a busca em
  // andamento — uma ação mais "cara" que só trocar de modo parado, então
  // pede um arrasto mais decidido (não só passar um pouco do limiar normal)
  // pra não se confundir com um toque de finalizar que teve um leve
  // tremor de mão. Fora da gravação continua exatamente igual, usando só
  // _commitThreshold — ver _onDragEnd.
  static const _cancelCommitThreshold = 90.0;
  static const _cancelCommitVelocity = 900.0;
  // Distância que o botão "sai" da tela antes de reaparecer do lado oposto
  // já no novo modo — dá a sensação de um botão saindo e outro entrando,
  // não só um teleporte.
  static const _exitOffset = 300.0;

  late final AnimationController _slideController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );
  Animation<double>? _slideAnimation;

  bool _isDragging = false;
  // Sem resistência nenhuma: o botão segue o dedo 1:1, exatamente na
  // distância que o dedo andou — testado com resistência (até com metade
  // da força) e não ficava natural, então foi removida de vez.
  double _liveDragDx = 0;

  double get _buttonOffset => _isDragging ? _liveDragDx : (_slideAnimation?.value ?? 0);

  /// Mapeamento fixo, não alternância: não existe um terceiro modo pra ficar
  /// girando — arrastar pra esquerda sempre aponta pra Cantar, pra direita
  /// sempre aponta pra Ouvir. Arrastar pro lado que já é o modo atual não
  /// faz nada (não tem "próximo" modo pra ir).
  ListenMode _targetModeForDirection(int direction) => direction < 0 ? ListenMode.hum : ListenMode.listen;

  @override
  void dispose() {
    _hintCycleActive = false; // impede um Future.delayed pendente de agir depois do dispose
    _slideController.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails details) {
    // Enquanto uma transição de troca de modo ainda está terminando, ignora
    // um novo arrasto — evita disparar duas trocas de modo encavaladas.
    if (_slideController.isAnimating) return;
    // Antes também bloqueava aqui se estivesse "recording" — agora o
    // arrasto pode começar durante a gravação/processamento também, pra
    // permitir trocar de modo na hora sem esperar terminar (ver
    // _onDragEnd). Continua seguro coexistindo com o toque de
    // finalizar/cancelar: um toque de verdade (sem deslocamento) nunca
    // chega a vencer o reconhecedor de arrasto, que só assume o gesto
    // depois de um deslocamento horizontal mínimo (touch slop do Flutter)
    // — é exatamente isso que faz as duas coexistirem sem disputa.

    setState(() {
      _isDragging = true;
      _liveDragDx = 0;
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    setState(() => _liveDragDx += details.delta.dx);
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (!_isDragging) return;
    final velocity = details.primaryVelocity ?? 0;
    final direction = _liveDragDx != 0 ? (_liveDragDx > 0 ? 1 : -1) : (velocity < 0 ? -1 : 1);
    final targetMode = _targetModeForDirection(direction);
    final currentMode = ref.read(listenControllerProvider).mode;
    final isRecording = ref.read(listenControllerProvider).status == ListenStatus.recording;

    // Fora da gravação, limiar normal (igual sempre foi). Durante a
    // gravação, o arrasto também cancela a busca — por ser uma ação mais
    // "cara", exige um deslocamento/velocidade maior (_cancelCommit*) pra
    // ficar claramente diferente de um toque de finalizar com tremor leve,
    // que o Flutter já trata como toque (não chega nem a dar início a um
    // arrasto) sempre que o dedo não se move o suficiente pra sair da
    // "área de toque" do próprio reconhecedor de gesto.
    final farEnough = isRecording
        ? (_liveDragDx.abs() > _cancelCommitThreshold || velocity.abs() > _cancelCommitVelocity)
        : (_liveDragDx.abs() > _commitThreshold || velocity.abs() > 700);
    // Antes o arrasto só "comitava" fora da gravação (!isRecording). Agora
    // também comita durante "ouvindo e buscando"/"processando" — arrastar
    // pro lado enquanto busca cancela a busca atual na hora e já troca de
    // modo, sem precisar esperar terminar.
    final shouldCommit = farEnough && targetMode != currentMode;

    setState(() => _isDragging = false);

    if (shouldCommit) {
      if (isRecording) {
        // Cancela e ESPERA terminar antes de animar a troca — cancelRecording
        // é local (só para o microfone, sem rede), então isso é rápido e
        // evita uma corrida em que a animação de saída (260ms) terminaria
        // antes do cancelamento, e o setMode no fim da animação seria
        // ignorado por ainda ver status == recording.
        await ref.read(listenControllerProvider.notifier).cancel();
      }
      _animateCommit(direction, targetMode);
    } else {
      _animateSpringBack();
    }
  }

  /// Arrasto curto/fraco demais (ou gravando) — volta suavemente pro centro,
  /// com um leve "quique" (easeOutBack) pra parecer elástico, não travado.
  void _animateSpringBack() {
    _slideAnimation = Tween<double>(begin: _liveDragDx, end: 0)
        .chain(CurveTween(curve: Curves.easeOutBack))
        .animate(_slideController);
    _slideController.forward(from: 0);
  }

  /// Arrasto confirmado: termina de "sair" na direção que já estava indo,
  /// troca pro `targetMode` no instante em que sai de vista, e reaparece do
  /// lado oposto deslizando de volta ao centro já com o novo modo.
  void _animateCommit(int direction, ListenMode targetMode) {
    _slideAnimation = Tween<double>(begin: _liveDragDx, end: direction * _exitOffset)
        .chain(CurveTween(curve: Curves.easeIn))
        .animate(_slideController);

    _slideController.forward(from: 0).whenComplete(() {
      if (!mounted) return;
      ref.read(listenControllerProvider.notifier).setMode(targetMode);

      _slideAnimation = Tween<double>(begin: -direction * _exitOffset, end: 0)
          .chain(CurveTween(curve: Curves.easeOutBack))
          .animate(_slideController);
      _slideController.forward(from: 0);
    });
  }

  /// SnackBar com a identidade visual do app (fundo surface escuro, cantos
  /// arredondados, barrinha colorida lateral) em vez do SnackBar cinza
  /// padrão do Material — pra qualquer mensagem parecer parte do app, não
  /// um alerta de sistema genérico. `accent` pode ser um gradiente (mensagem
  /// descontraída de "não encontrado", colorida por modo) ou uma cor sólida
  /// (erro, sempre vermelho — não teria sentido "zoar" um erro de verdade).
  void _showBrandedSnackBar(BuildContext context, String message, {Gradient? gradient, Color? solidColor}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surface,
        elevation: 6,
        margin: const EdgeInsets.all(16),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(seconds: 4),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 6,
              decoration: BoxDecoration(
                color: solidColor,
                gradient: gradient,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                child: Text(
                  message,
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.35),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(listenControllerProvider);
    final controller = ref.read(listenControllerProvider.notifier);
    // TEMPORÁRIO — diagnóstico (ver debugStopReasonProvider em app_providers.dart).
    final debugStopReason = ref.watch(debugStopReasonProvider);

    ref.listen(listenControllerProvider, (previous, next) {
      if (next.result != null && previous?.result != next.result) {
        context.push('/result', extra: next.result).then((_) => controller.reset());
      }
      // Só escolhe a próxima frase na TRANSIÇÃO real pra "não encontrado"
      // (nunca dentro do build, que pode rodar de novo por outros motivos
      // e avançaria a alternância sem uma busca nova de verdade ter
      // acontecido).
      if (next.status == ListenStatus.notFound && previous?.status != ListenStatus.notFound) {
        setState(() => _currentNotFoundMessage = _nextNotFoundMessage(next.mode));
      }
      // "Não encontrado" já aparece no texto de status principal (abaixo do
      // botão) — SnackBar separada pra isso era redundante, a mesma
      // informação aparecendo duas vezes na tela ao mesmo tempo.
      if (next.status == ListenStatus.error && next.errorMessage != null) {
        _showBrandedSnackBar(context, next.errorMessage!, solidColor: AppColors.error);
      }
      // Loop de dicas: ativo em QUALQUER modo enquanto grava de verdade
      // (não durante "Processando..."). Começa/reinicia do zero só na
      // transição real de entrada (ou se o modo mudou no meio, caso
      // extremo que hoje não acontece na prática — trocar de modo sempre
      // cancela a gravação antes —, mas fica protegido mesmo assim), e
      // para assim que sai dessa condição (parou de gravar ou entrou em
      // "Processando...").
      final wasRecordingWithHints = previous?.status == ListenStatus.recording && previous?.isProcessing == false;
      final isRecordingWithHints = next.status == ListenStatus.recording && !next.isProcessing;
      final modeChangedMidCycle = wasRecordingWithHints && isRecordingWithHints && previous?.mode != next.mode;
      if ((isRecordingWithHints && !wasRecordingWithHints) || modeChangedMidCycle) {
        _startHintCycle(next.mode);
      } else if (!isRecordingWithHints && wasRecordingWithHints) {
        _stopHintCycle();
      }
    });

    final statusLabel = switch (state.status) {
      ListenStatus.idle => state.mode == ListenMode.listen
          ? 'Ouça a música e... Salabim !!'
          : 'Cante ou toque a música e... Salabim !!',
      // "Processando" quando a gravação já parou de verdade e só falta a
      // resposta do servidor — antes mostrava o mesmo texto de "ouvindo"
      // nas duas fases, dando a impressão de gravação travada mesmo já
      // tendo parado.
      ListenStatus.recording => state.isProcessing
          ? 'Processando...'
          : 'Ouvindo e buscando... (tentativa ${state.attempt + 1})',
      ListenStatus.notFound => _currentNotFoundMessage,
      ListenStatus.error => 'Algo deu errado',
    };

    final isRecording = state.status == ListenStatus.recording;
    // Enquanto grava de verdade, em qualquer modo, a área de status/dica
    // vira o loop de frases daquele modo (ver _hintPhrasesFor) — substitui
    // tanto o texto de status quanto a dica pequena que existiam separados
    // antes.
    final isHintCycleActive = isRecording && !state.isProcessing;
    // Mesma fonte (Baloo 2) e mesma opacidade (_hintMaxOpacity) do loop de
    // dicas em quase todos os estados — idle mantém o tamanho original
    // (15px); "Processando..." e "não encontrado" usam o mesmo 22px do
    // loop de dicas (pedido do usuário). Erro continua com o estilo de
    // sempre (não foi pedido).
    final statusTextStyle = _statusTextStyleFor(state.status);

    // Toca em qualquer lugar da tela pra encerrar a gravação (Cantar) ou
    // cancelar (Ouvir) — mesma lógica que já existia no botão, só que agora
    // é a área de toque VÁLIDA pra essa ação inteira, não só o botão.
    void handleScreenTapWhileRecording() {
      if (state.mode == ListenMode.hum) {
        // Cantar: ENCERRA a gravação na hora (não cancela) — usa o que já
        // foi cantado até aqui pra buscar, sem esperar o silêncio ser
        // detectado ou o tempo máximo acabar. Sem efeito se já estiver
        // "Processando..." (gravação já parou, nada mais a encerrar).
        controller.finishRecordingNow();
      } else {
        // Ouvir: continua cancelando — a busca já acontece sozinha em
        // segmentos curtos automáticos, não precisa desse controle manual.
        unawaited(controller.cancel());
      }
    }

    // Solução definitiva pro toque de finalizar não competir com o arrasto
    // de trocar de modo — em vez de tentar prever quem "vence" a disputa de
    // gestos do Flutter (ambíguo com dois GestureDetectors sobrepostos),
    // as duas coexistem no MESMO GestureDetector e ficam naturalmente
    // desambiguadas pelo próprio mecanismo de arena de gestos do Flutter:
    //
    // - Tocar em qualquer lugar (finalizar/cancelar) só fica ativo QUANDO
    //   está gravando (onTap só existe nesse momento) — igual antes.
    // - Arrastar (trocar de modo) agora fica ativo SEMPRE, inclusive
    //   durante "ouvindo e buscando"/"processando" — arrastar pro lado
    //   nessas fases cancela a busca atual na hora e já troca de modo, sem
    //   precisar esperar terminar (ver _onDragEnd). Antes ficava bloqueado
    //   enquanto gravava.
    // - Um toque de verdade (sem deslocamento horizontal) nunca é
    //   confundido com arrasto: o reconhecedor de arrasto só assume o
    //   gesto depois de um deslocamento mínimo (touch slop do Flutter),
    //   então onTap continua disparando normalmente pra toques parados.
    // - O botão em si fica dentro de um IgnorePointer enquanto grava — o
    //   toque nele passa DIRETO pra esse GestureDetector externo, sem
    //   nenhum reconhecedor concorrente por baixo pra disputar. Garantido
    //   pelo próprio Flutter, não por suposição de prioridade de gestos.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onTap: isRecording ? handleScreenTapWhileRecording : null,
      child: Column(
        children: [
          // Só o texto "Salabim" agora, sem o ícone do mago — ele já
          // aparece no botão central, ficava redundante mostrar duas vezes.
          // Recortado direto do arquivo da logo de verdade (não uma fonte
          // parecida) — ver assets/icons/salabim_wordmark.png, gerado a
          // partir de salabim_logo_lockup.png removendo só a parte do
          // ícone. Spacer (não mais um SizedBox fixo) tanto antes quanto
          // depois: centraliza o texto no espaço vazio do topo, em vez de
          // grudado lá em cima.
          const Spacer(),
          Image.asset('assets/icons/salabim_wordmark.png', height: 56, fit: BoxFit.contain),
          const Spacer(),
          // Mesmo raciocínio do botão: enquanto grava, o seletor de modo já
          // fica inerte de qualquer forma (controller.setMode ignora troca
          // durante gravação) — o IgnorePointer só garante que o toque
          // nessa área específica da tela passe direto pro GestureDetector
          // externo (finalizar/cancelar), sem disputa de gesto nenhuma.
          IgnorePointer(
            ignoring: isRecording,
            child: ModeSelector(mode: state.mode, onChanged: controller.setMode),
          ),
          const Spacer(),
          AnimatedBuilder(
            animation: _slideController,
            builder: (context, child) => Transform.translate(
              offset: Offset(_buttonOffset, 0),
              child: child,
            ),
            child: IgnorePointer(
              // Enquanto grava, o botão fica invisível pro toque — o toque
              // atravessa ele direto pro GestureDetector externo acima, sem
              // nenhuma disputa de gesto possível.
              ignoring: isRecording,
              child: PulseButton(
                mode: state.mode,
                isRecording: isRecording,
                isProcessing: state.isProcessing,
                amplitude: state.amplitude,
                // Só relevante quando NÃO grava (o IgnorePointer acima já
                // bloqueia isso durante a gravação) — inicia a escuta.
                onTap: controller.startListening,
              ),
            ),
          ),
          // Espaçador flexível (não mais um SizedBox fixo de 24) — antes o
          // texto ficava colado no botão, com um vão vazio grande sobrando
          // embaixo, perto do menu inferior. Agora esse espaço é dividido
          // de forma equilibrada entre "acima do texto" e "abaixo do
          // texto" (ver Spacer no final da coluna), centralizando a dica
          // no vão entre o botão e o menu, em vez de grudada no botão.
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            // Gravando de verdade (qualquer modo): loop de dicas — some por
            // completo (opacidade máxima -> 0), só DEPOIS troca a frase e
            // aparece de novo (0 -> opacidade máxima). Nunca crossfade (as
            // duas nunca ficam parcialmente visíveis ao mesmo tempo) — ver
            // _onHintFadeEnd. Fonte "Baloo 2": redonda e bem mais robusta
            // que a Inter do resto do app, de propósito — só aqui, pra
            // essas dicas terem uma personalidade mais jovem/brincalhona
            // (combina com o resto da identidade do app: o mago, os
            // emojis) sem mudar a tipografia do app inteiro. Fora disso, o
            // texto de status de sempre (idle, Processando, não encontrado,
            // erro), na fonte padrão.
            child: isHintCycleActive
                ? AnimatedOpacity(
                    opacity: _hintVisible ? _hintMaxOpacity : 0.0,
                    duration: _hintFadeDuration,
                    curve: Curves.easeInOut,
                    onEnd: _onHintFadeEnd,
                    child: Text(
                      _hintPhrasesFor(_hintMode)[_hintIndex],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.baloo2(
                        color: AppColors.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  )
                : Text(
                    statusLabel,
                    textAlign: TextAlign.center,
                    style: statusTextStyle,
                  ),
          ),
          // TEMPORÁRIO — diagnóstico do motivo/tempo em que a gravação do
          // Cantar parou (ver debugStopReasonProvider em app_providers.dart).
          // Só aparece quando há um motivo registrado nessa sessão. Remover
          // assim que acharmos a causa do corte prematuro relatado em
          // 13/ago/2026.
          if (debugStopReason != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '🐛 $debugStopReason',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.error, fontSize: 11),
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }
}
