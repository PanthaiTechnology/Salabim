import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
import '../data/services/api_client.dart';
import '../data/services/audio_recorder_service.dart';
import '../data/services/history_service.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final historyServiceProvider = Provider<HistoryService>((ref) => HistoryService());

final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final service = AudioRecorderService();
  ref.onDispose(service.dispose);
  return service;
});

/// Estado da tela de escuta: idle -> recording (busca em tempo real, em
/// segmentos, sem precisar soltar o botão) -> result/notFound/error.
enum ListenStatus { idle, recording, notFound, error }

class ListenState {
  final ListenStatus status;
  final ListenMode mode;
  final double amplitude;
  final int attempt;
  final String? errorMessage;
  final Track? result;
  // Diferencia "ainda gravando" de "gravação já parou, esperando resposta
  // do servidor" — antes as duas fases mostravam o mesmo texto/animação
  // ("Ouvindo e buscando...", botão pulsando), dando a impressão de que a
  // gravação continuava mesmo depois de já ter parado de verdade.
  final bool isProcessing;

  const ListenState({
    this.status = ListenStatus.idle,
    this.mode = ListenMode.listen,
    this.amplitude = 0.0,
    this.attempt = 0,
    this.errorMessage,
    this.result,
    this.isProcessing = false,
  });

  ListenState copyWith({
    ListenStatus? status,
    ListenMode? mode,
    double? amplitude,
    int? attempt,
    String? errorMessage,
    Track? result,
    bool? isProcessing,
  }) {
    return ListenState(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      amplitude: amplitude ?? this.amplitude,
      attempt: attempt ?? this.attempt,
      errorMessage: errorMessage,
      result: result ?? this.result,
      isProcessing: isProcessing ?? this.isProcessing,
    );
  }
}

/// Controla o ciclo de escuta contínua: assim que o usuário toca uma vez,
/// grava um trecho curto, já começa a gravar o próximo trecho, e em
/// paralelo manda o trecho anterior pro backend. O resultado aparece assim
/// que QUALQUER trecho bater — sem precisar tocar de novo pra parar. O
/// usuário só interage de novo se quiser cancelar antes da hora.
class ListenController extends StateNotifier<ListenState> {
  ListenController(this._recorder, this._api) : super(const ListenState());

  final AudioRecorderService _recorder;
  final ApiClient _api;

  /// Ouvir: durações CRESCENTES por tentativa (não mais um número fixo
  /// repetido) — decidido com base num teste controlado (14/ago/2026, ver
  /// ARCHITECTURE.md §4.3): pegamos uma gravação real onde o Shazam
  /// reconhecia e o Salabim não, e testamos o MESMO trecho na AudD com
  /// durações crescentes a partir do início. Resultado: 4-8s não achava
  /// nada; **10-14s achava uma música ERRADA com confiança** (o motor não
  /// fica em silêncio quando tem contexto "no meio do caminho", ele
  /// arrisca um palpite); só a partir de ~16s acertava de forma
  /// consistente. Por isso a 1ª tentativa é curta (rápida pros casos
  /// fáceis, perto da caixa — nesse patamar o teste mostrou "nada" em vez
  /// de "errado", então é seguro tentar curto primeiro) e a 2ª pula
  /// DIRETO pra 18s, evitando de propósito a faixa de 10-14s que se
  /// mostrou perigosa (risco real de aceitar uma resposta errada com
  /// confiança antes de dar tempo da tentativa longa, que é a correta,
  /// rodar). "Parar cedo se achar rápido" já é automático: o
  /// pipeline aceita o primeiro resultado não-vazio de qualquer tentativa,
  /// então um acerto na 1ª tentativa (curta) encerra a sessão na hora, sem
  /// esperar a 2ª.
  ///
  /// 1ª tentativa reduzida de 6s pra 2s (14/ago/2026, a pedido do usuário —
  /// 6s estava parecendo demorado demais pro caso fácil). Risco aceitável:
  /// no teste controlado, 4s já dava "nada" (não "errado"), então 2s deve
  /// se comportar igual (silêncio, não confusão) nos casos em que não é
  /// suficiente — só teria menos chance de acertar de primeira num caso
  /// fácil, sem ficar mais arriscado.
  static const _listenSegmentDurations = [Duration(seconds: 2), Duration(seconds: 18)];

  /// Cantar usa 60s — não é mais um teto "normal" pra parar de gravar, e
  /// sim um limite de segurança bem folgado: o pedido explícito é que a
  /// gravação SÓ termine pelo toque manual ("toque para finalizar e
  /// buscar") ou pelos 5s de silêncio abaixo — quanto mais a pessoa canta,
  /// mais contexto melódico o ACRCloud tem pra acertar, então não faz
  /// sentido cortar por tempo enquanto ela ainda está cantando.
  Duration _segmentDurationFor(ListenMode mode, int attemptIndex) {
    if (mode == ListenMode.hum) return const Duration(seconds: 60);
    final i = attemptIndex.clamp(0, _listenSegmentDurations.length - 1);
    return _listenSegmentDurations[i];
  }

  /// Quantos trechos tenta no total antes de desistir. Cantar é 1 tentativa
  /// única: uma gravação contínua tem muito mais contexto melódico pro
  /// ACRCloud reconhecer do que várias fatiadas — testado na prática,
  /// precisão caiu de verdade com 3 tentativas menores. A detecção de
  /// silêncio (abaixo) já resolve "não fica esperando à toa" sem precisar
  /// fatiar a gravação. Ouvir: uma tentativa por duração em
  /// _listenSegmentDurations.
  int _maxAttemptsFor(ListenMode mode) => mode == ListenMode.hum ? 1 : _listenSegmentDurations.length;

  // Detecção de silêncio — só no modo Cantar: se a pessoa já começou a
  // cantar e depois passa a maior parte dos últimos 5s calada, entende que
  // ela terminou e corta a gravação na hora.
  //
  // "Voz" e "silêncio" NÃO são um número fixo de amplitude — testado na
  // prática (14/ago/2026), um piso fixo (0.15) não generaliza: em ambiente
  // barulhento o ruído de fundo nunca cai abaixo dele (silêncio nunca
  // dispara), e em ambiente muito quieto qualquer sopro passaria como
  // "voz". Em vez disso, cada gravação calibra sozinha o piso de ruído do
  // próprio ambiente, e "voz" é definida como uma margem ACIMA desse piso
  // — o que importa é o CONTRASTE entre a voz da pessoa e o fundo, não um
  // volume absoluto.
  //
  // A exigência de "silêncio" também NÃO é mais um trecho contínuo sem
  // nenhuma interrupção — testado na prática nos dois sentidos (14/ago/2026):
  // exigir um trecho 100% contínuo é frágil, porque qualquer som breve
  // (ruído ambiente periódico) resetava tudo do zero; e a tentativa de
  // corrigir isso com um "debounce" (só resetar se o som persistisse por
  // tempo mínimo) piorou pro lado oposto — um debounce longo o bastante
  // pra ignorar ruído também engolia palavras/notas curtas cantadas de
  // verdade, fazendo parecer silêncio mesmo com a pessoa ainda cantando
  // (só picotado, com pausas naturais entre frases). Em vez de exigir
  // continuidade perfeita, mede a DENSIDADE de voz na janela dos últimos
  // 5s: só considera que a pessoa parou se quase nada dessa janela teve
  // voz de verdade. Isso tolera tanto ruído ambiente esporádico (poucas
  // amostras isoladas) quanto canto picotado (muitas amostras de voz
  // espalhadas, mesmo com pausas).
  // O piso desce imediatamente ao ouvir algo mais quieto que ele (silêncio
  // de verdade nunca é "ruído", então é seguro confiar na hora), mas só
  // sobe bem devagar com o tempo — caso o ambiente realmente fique mais
  // barulhento no meio da gravação (carro passando, tv ligada por perto).
  // Sem esse teto de subida, um pico alto isolado não empurra o piso (ele
  // só reage a amostras MAIS BAIXAS que o piso atual, nunca mais altas).
  static const _noiseFloorDecayPerSecond = 0.003;
  // Testado na prática (14/ago/2026, 4ª rodada): usuário confirmou
  // silêncio real de 7-8s com ventilador ligado e janela aberta, e mesmo
  // assim não disparou — uma margem FIXA acima do piso (0.18) não dá conta
  // de ambientes com ruído variável (o piso captura o valor mais baixo já
  // visto, mas não o quanto esse ruído costuma OSCILAR). A margem virou
  // proporcional ao CONTRASTE real entre o piso de ruído e o nível de voz
  // do próprio usuário, calibrado a partir do canto dele mesmo assim que
  // detectado (ver _voiceLevelEstimate) — quem canta bem mais alto que o
  // ambiente ganha uma margem generosa (tolera ruído bem variável sem
  // confundir); quem canta mais baixo, mais perto do piso, ganha uma
  // margem mais apertada (não tem como pedir mais separação do que existe
  // fisicamente entre a voz da pessoa e o ambiente dela).
  // Testado na prática (14/ago/2026, 5ª rodada): com fração 0.35, piso 0.07
  // e voz calibrada em 0.34, o limiar saía em 0.165 — mais PERTO do piso de
  // ruído do que do nível de voz, ou seja, mais fácil ainda do ruído ser
  // confundido com voz (o oposto do que se queria). Fração corrigida pra
  // deixar o limiar mais perto do nível de voz (mais difícil de cruzar por
  // ruído), mantendo folga suficiente abaixo da voz de verdade.
  // Testado na prática (14/ago/2026, 6ª rodada): 1ª busca calibrou piso
  // 0.07 e voz 0.81 (funcionou, disparou em 14%); 2ª busca LOGO EM SEGUIDA,
  // no mesmo ambiente (piso recalibrou pro mesmo 0.07, prova que cada
  // busca calibra do zero, não reaproveita a anterior), calibrou voz só
  // 0.39 — a pessoa cantou mais baixo dessa vez. Com fração 0.65, esse
  // "espaço" menor (0.07↔0.39) deu uma margem fina (~0.21), insuficiente
  // de novo. A fração continua certa (calibra por sessão, como deve ser)
  // — o que faltava era um piso MÍNIMO de margem informado pelo histórico
  // real: em nenhum teste de hoje, em nenhum ambiente, a voz cantada
  // ficou abaixo de ~0.33. Um mínimo de 0.22 garante folga confortável
  // abaixo disso mesmo quando a calibração daquela sessão específica sair
  // "curta".
  static const _voiceThresholdFraction = 0.65; // posição do limiar entre piso e nível de voz observado
  static const _minVoiceMargin = 0.22; // nunca menor que isso, mesmo com pouco contraste calibrado (era 0.12)
  static const _voiceLevelSmoothingAlpha = 0.08; // atualização bem lenta — não deixa 1 pico desregular a estimativa
  static const _silenceDurationToStop = Duration(seconds: 5); // tamanho da janela de análise
  // Só dispara se a fração de amostras "voz" na janela ficar EM OU ABAIXO
  // disso — 15% de uma janela de 5s equivale a até ~750ms de voz espalhada
  // (ruído esporádico cabe folgado aqui) sem impedir a detecção; qualquer
  // canto de verdade, mesmo picotado, fica bem acima disso na prática.
  static const _silenceVoiceFractionThreshold = 0.15;
  // Testado na prática (14/ago/2026, 3ª rodada): usuário confirmou ter
  // ficado 7-8s em silêncio total de verdade, mas a densidade de voz na
  // janela nunca caiu abaixo de 69% — a leitura de amplitude "pulando"
  // entre valores baixos e altos logo depois de parar de cantar é a
  // assinatura clássica do AGC (controle automático de ganho) do
  // microfone "bombeando" enquanto se readapta ao silêncio, amplificando
  // o ruído residual de forma instável por alguns segundos. Suaviza a
  // leitura (média móvel exponencial) antes de classificar voz/silêncio,
  // pra filtrar esse chacoalhar sem atrasar a resposta de verdade (janela
  // de suavização bem curta, não confundir com o debounce de 1.5s que já
  // se mostrou problemático). 0.3 sozinho não foi suficiente (testado na
  // prática, 5ª rodada) — reduzido pra suavizar mais forte.
  static const _amplitudeSmoothingAlpha = 0.15;

  double _noiseFloor = 0.0;
  DateTime _noiseFloorUpdatedAt = DateTime.now();
  double? _smoothedAmplitude;
  // Nível de voz do próprio usuário, calibrado ao vivo a partir das
  // amostras que já foram classificadas como voz (ver _checkForSilence) —
  // é o outro lado do contraste piso-de-ruído/voz que define o limiar.
  double? _voiceLevelEstimate;
  bool _hasDetectedVoice = false;
  DateTime? _firstVoiceDetectedAt;
  // Amostras (instante, era voz?) dos últimos _silenceDurationToStop —
  // amostras mais antigas são descartadas a cada nova leitura.
  final List<MapEntry<DateTime, bool>> _recentAmplitudeSamples = [];

  StreamSubscription<double>? _amplitudeSub;
  bool _sessionActive = false;

  // Sinalizador da gravação atual (modo Cantar) — completa cedo tanto pela
  // detecção automática de silêncio quanto por um toque manual do usuário
  // em finishRecordingNow(). Fica em nível de instância (não só local
  // dentro de _recordAndSearchSegment) justamente pra o toque manual
  // conseguir alcançá-lo de fora.
  Completer<void>? _stopEarlySignal;

  void setMode(ListenMode mode) {
    if (state.status == ListenStatus.recording) return;
    state = state.copyWith(mode: mode);
  }

  /// Único ponto de entrada: um toque começa a escuta contínua. Não existe
  /// um segundo toque "obrigatório" pra buscar — a busca já acontece
  /// automaticamente a cada segmento gravado.
  ///
  /// Guarda contra sessão dupla: bug real encontrado em teste — um toque
  /// duplo (ou conflito entre o gesto de deslizar do botão e o toque)
  /// conseguia disparar `startListening` duas vezes antes da UI atualizar
  /// pra "gravando", criando duas gravações simultâneas que atropelavam
  /// uma à outra (uma delas cortada em ~1s) e duas buscas concorrentes —
  /// parecia resultado de cache errado, mas era sessão duplicada. Esse
  /// `if` torna a função segura mesmo se chamada mais de uma vez seguida.
  Future<void> startListening() async {
    if (_sessionActive) return;
    _sessionActive = true;
    state = state.copyWith(
      status: ListenStatus.recording,
      errorMessage: null,
      result: null,
      attempt: 0,
      isProcessing: false,
    );
    await _recordAndSearchSegment();
  }

  Future<void> _recordAndSearchSegment() async {
    if (!_sessionActive) return;

    _hasDetectedVoice = false;
    _firstVoiceDetectedAt = null;
    _recentAmplitudeSamples.clear();
    _noiseFloor = 0.0; // recalibra do zero a cada gravação — ambiente pode ter mudado
    _noiseFloorUpdatedAt = DateTime.now();
    _smoothedAmplitude = null;
    _voiceLevelEstimate = null;
    // Sinalizador que completa cedo tanto pela detecção automática de
    // silêncio (5s calado depois de já ter cantado) quanto por um toque
    // manual do usuário em finishRecordingNow() — corrida contra o timer
    // de duração máxima do trecho, o que vier primeiro.
    final stopEarly = Completer<void>();
    _stopEarlySignal = stopEarly;

    await _amplitudeSub?.cancel();
    _amplitudeSub = _recorder.startRecording(mode: state.mode).listen(
      (amp) {
        if (!_sessionActive) return;
        state = state.copyWith(amplitude: amp);
        if (state.mode == ListenMode.hum) {
          _checkForSilence(amp, stopEarly);
        }
      },
      onError: (_) {
        _sessionActive = false;
        state = state.copyWith(
          status: ListenStatus.error,
          errorMessage: 'Precisamos da permissão do microfone para identificar a música.',
        );
      },
    );

    final mode = state.mode;
    // state.attempt aqui ainda é o número de tentativas JÁ CONCLUÍDAS antes
    // dessa gravação começar (0 na 1ª chamada) — é o índice certo pra
    // escolher a duração crescente dessa tentativa (ver _segmentDurationFor).
    await Future.any([
      Future.delayed(_segmentDurationFor(mode, state.attempt)),
      stopEarly.future,
    ]);
    _stopEarlySignal = null;
    if (!_sessionActive) return;

    final file = await _recorder.stopRecording();
    final currentAttempt = state.attempt + 1;
    state = state.copyWith(attempt: currentAttempt);

    // Já dispara a gravação do próximo trecho antes de esperar a resposta
    // do servidor — assim a escuta continua fluida enquanto o trecho
    // anterior é identificado em paralelo, em vez de parar-esperar-parar.
    final hasMoreAttempts = currentAttempt < _maxAttemptsFor(mode);
    if (_sessionActive && hasMoreAttempts) {
      unawaited(_recordAndSearchSegment());
    } else if (_sessionActive) {
      // Última tentativa: não tem próximo trecho gravando em paralelo, o
      // microfone já parou de verdade — mostra "processando" em vez de
      // continuar parecendo que ainda está ouvindo (era a mesma aparência
      // das duas fases antes, dava a impressão de gravação travada).
      state = state.copyWith(isProcessing: true);
    }

    if (file == null) return;

    try {
      final track = await _api.identify(audioFile: file, mode: state.mode);
      if (!_sessionActive) return; // já achou em outro segmento ou foi cancelado

      if (track != null) {
        _sessionActive = false;
        await _amplitudeSub?.cancel();
        await _recorder.cancelRecording(); // encerra o próximo trecho já em andamento
        state = state.copyWith(status: ListenStatus.idle, result: track, isProcessing: false);
        return;
      }
    } on IdentifyException catch (e) {
      if (!_sessionActive) return;
      _sessionActive = false;
      await _amplitudeSub?.cancel();
      await _recorder.cancelRecording();
      state = state.copyWith(status: ListenStatus.error, errorMessage: e.message, isProcessing: false);
      return;
    }

    // Esse trecho não bateu. Se não há mais tentativas agendadas, desiste.
    if (_sessionActive && !hasMoreAttempts) {
      _sessionActive = false;
      await _amplitudeSub?.cancel();
      state = state.copyWith(status: ListenStatus.notFound, isProcessing: false);
      // Volta sozinho pro estado padrão depois de 5s — a mensagem de "não
      // encontrado" já é auto-explicativa na hora, não precisa ficar presa
      // na tela até o usuário tocar de novo. Só reseta se ainda estiver
      // nesse mesmo estado (não pisa em cima de uma sessão nova que o
      // usuário já tenha começado nesse meio-tempo).
      Future.delayed(const Duration(seconds: 5), () {
        if (state.status == ListenStatus.notFound) reset();
      });
    }
  }

  /// Roda a cada nova leitura de amplitude (a cada ~100ms) enquanto grava
  /// no modo Cantar. "Voz" e "silêncio" são relativos ao piso de ruído
  /// calibrado nessa própria gravação (ver comentário nos campos acima),
  /// não um número fixo — assim funciona tanto num quarto silencioso
  /// quanto numa rua barulhenta. Só começa a contar silêncio depois que a
  /// pessoa já cantou pelo menos uma vez (silêncio antes de começar não
  /// conta, senão cortaria a gravação assim que ela tocasse o botão).
  void _checkForSilence(double amplitude, Completer<void> stopEarly) {
    if (stopEarly.isCompleted) return;
    final now = DateTime.now();

    // Suaviza a leitura bruta (média móvel exponencial, ver
    // _amplitudeSmoothingAlpha) antes de qualquer outra coisa — filtra o
    // "chacoalhar" do AGC do microfone sem atrasar a resposta de verdade
    // (janela de suavização bem curta). Tudo abaixo usa esse valor
    // suavizado, não a leitura bruta.
    final smoothed = _smoothedAmplitude == null
        ? amplitude
        : _smoothedAmplitude! + (amplitude - _smoothedAmplitude!) * _amplitudeSmoothingAlpha;
    _smoothedAmplitude = smoothed;

    // Recalibra o piso de ruído: desce na hora se ouvir algo mais quieto
    // que o piso atual, sobe só bem devagar com o tempo (ver comentário
    // em _noiseFloorDecayPerSecond).
    if (smoothed <= _noiseFloor) {
      _noiseFloor = smoothed;
      _noiseFloorUpdatedAt = now;
    } else {
      final secondsSinceUpdate = now.difference(_noiseFloorUpdatedAt).inMilliseconds / 1000.0;
      final drifted = (_noiseFloor + _noiseFloorDecayPerSecond * secondsSinceUpdate).clamp(0.0, 1.0);
      if (drifted > _noiseFloor) {
        _noiseFloor = drifted;
        _noiseFloorUpdatedAt = now;
      }
    }

    // Limiar de voz = ponto entre o piso de ruído e o nível de voz do
    // usuário (calibrado ao vivo abaixo) — o CONTRASTE real entre os dois,
    // não uma margem fixa. Antes de calibrar (ainda não ouvimos nenhuma
    // amostra de voz nessa gravação), usa um chute conservador só pra dar
    // o pontapé inicial.
    final referenceVoiceLevel = _voiceLevelEstimate ?? (_noiseFloor + 0.30);
    final dynamicMargin =
        (_voiceThresholdFraction * (referenceVoiceLevel - _noiseFloor)).clamp(_minVoiceMargin, 1.0);
    final voiceThreshold = (_noiseFloor + dynamicMargin).clamp(0.0, 1.0);
    final isVoice = smoothed >= voiceThreshold;
    if (isVoice) {
      _hasDetectedVoice = true;
      _firstVoiceDetectedAt ??= now;
      // Refina a estimativa do nível de voz do usuário com essa amostra —
      // suaviza bem devagar, uma amostra isolada não deve desregular a
      // calibração inteira.
      _voiceLevelEstimate =
          _voiceLevelEstimate == null ? smoothed : _voiceLevelEstimate! + (smoothed - _voiceLevelEstimate!) * _voiceLevelSmoothingAlpha;
    }

    if (!_hasDetectedVoice) return; // silêncio antes de começar a cantar, ignora

    // Guarda essa amostra na janela e descarta as que já saíram dos
    // últimos _silenceDurationToStop.
    _recentAmplitudeSamples.add(MapEntry(now, isVoice));
    final windowStart = now.subtract(_silenceDurationToStop);
    _recentAmplitudeSamples.removeWhere((sample) => sample.key.isBefore(windowStart));

    // Só avalia depois de ter uma janela cheia de verdade (pelo menos
    // _silenceDurationToStop desde que a pessoa começou a cantar) — senão
    // pararia cedo demais logo no início, antes de dar tempo de acumular
    // amostras suficientes pra julgar a densidade.
    if (now.difference(_firstVoiceDetectedAt!) < _silenceDurationToStop) return;

    final (voiceFraction, _) = _computeVoiceDensity(now);

    if (voiceFraction <= _silenceVoiceFractionThreshold) {
      stopEarly.complete();
    }
  }

  /// Densidade de voz (0.0-1.0) na janela dos últimos _silenceDurationToStop,
  /// medida por TEMPO real (ms) que cada estado durou — não por contagem de
  /// amostras, que assume implicitamente um intervalo perfeitamente regular
  /// entre leituras (~100ms). Na prática esse intervalo pode não ser
  /// regular (o app pode receber leituras em cadência irregular), o que
  /// faria a contagem simples dar peso desigual a cada amostra e distorcer
  /// o resultado. Somar a duração real de cada estado até a próxima leitura
  /// (ou até agora, pra última) é imune a essa irregularidade. Retorna
  /// também o total de ms cobertos pela janela, só pra diagnóstico
  /// (confirma se a janela realmente está cobrindo os 5s esperados).
  (double, int) _computeVoiceDensity(DateTime now) {
    var voiceMs = 0;
    var totalMs = 0;
    for (var i = 0; i < _recentAmplitudeSamples.length; i++) {
      final sample = _recentAmplitudeSamples[i];
      final nextTime = i + 1 < _recentAmplitudeSamples.length ? _recentAmplitudeSamples[i + 1].key : now;
      final dt = nextTime.difference(sample.key).inMilliseconds;
      totalMs += dt;
      if (sample.value) voiceMs += dt;
    }
    return (totalMs > 0 ? voiceMs / totalMs : 0.0, totalMs);
  }

  /// Toque manual do usuário pra encerrar a gravação do modo Cantar antes
  /// da hora — sem mudar nada dos parâmetros técnicos de análise (duração
  /// máxima, detecção de silêncio continuam do jeito que estão). Isso só
  /// dá ao usuário um jeito de dizer "já cantei o suficiente, pode buscar
  /// agora" sem precisar esperar o silêncio ser detectado ou o tempo
  /// máximo acabar. Usa o mesmo sinalizador que a detecção de silêncio já
  /// usa internamente — funciona exatamente como se o silêncio tivesse
  /// sido detectado nesse instante. Sem efeito se já não estiver mais
  /// gravando de verdade (ex: chamado de novo durante "Processando...").
  void finishRecordingNow() {
    if (state.mode != ListenMode.hum || state.status != ListenStatus.recording) return;
    final signal = _stopEarlySignal;
    if (signal != null && !signal.isCompleted) {
      signal.complete();
    }
  }

  /// Cancela a escuta antes da hora (o usuário tocou de novo no botão
  /// enquanto ainda estava buscando).
  Future<void> cancel() async {
    _sessionActive = false;
    await _amplitudeSub?.cancel();
    await _recorder.cancelRecording();
    state = const ListenState();
  }

  void reset() {
    state = ListenState(mode: state.mode);
  }
}

final listenControllerProvider = StateNotifierProvider<ListenController, ListenState>((ref) {
  return ListenController(ref.watch(audioRecorderProvider), ref.watch(apiClientProvider));
});
