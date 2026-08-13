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

// TEMPORÁRIO — diagnóstico pra achar por que o modo Cantar às vezes encerra
// a gravação sozinho bem antes do esperado, sem toque manual e sem silêncio
// real (relatado em 13/ago/2026). ListenController escreve aqui o motivo e o
// tempo decorrido assim que a gravação para; listen_screen.dart mostra esse
// texto embaixo de "Processando...". Fora do ListenState/copyWith de
// propósito — não queria arriscar mexer no padrão de merge que os outros
// campos já usam só por causa de um campo temporário. Remover (aqui, no
// controller e na tela) assim que acharmos a causa real.
final debugStopReasonProvider = StateProvider<String?>((ref) => null);

/// Controla o ciclo de escuta contínua: assim que o usuário toca uma vez,
/// grava um trecho curto, já começa a gravar o próximo trecho, e em
/// paralelo manda o trecho anterior pro backend. O resultado aparece assim
/// que QUALQUER trecho bater — sem precisar tocar de novo pra parar. O
/// usuário só interage de novo se quiser cancelar antes da hora.
class ListenController extends StateNotifier<ListenState> {
  ListenController(this._recorder, this._api, this._ref) : super(const ListenState());

  final AudioRecorderService _recorder;
  final ApiClient _api;
  final Ref _ref;

  /// Duração de cada trecho gravado e enviado pro backend. Ouvir continua
  /// 4s (segmentos curtos, várias tentativas). Cantar agora usa 60s — não é
  /// mais um teto "normal" pra parar de gravar, e sim um limite de
  /// segurança bem folgado: o pedido explícito é que a gravação SÓ termine
  /// pelo toque manual ("toque para finalizar e buscar") ou pelos 5s de
  /// silêncio abaixo — quanto mais a pessoa canta, mais contexto melódico
  /// o ACRCloud tem pra acertar, então não faz sentido cortar por tempo
  /// enquanto ela ainda está cantando.
  Duration _segmentDurationFor(ListenMode mode) =>
      mode == ListenMode.hum ? const Duration(seconds: 60) : const Duration(seconds: 4);

  /// Quantos trechos tenta no total antes de desistir. Cantar voltou a ser
  /// 1 tentativa única: uma gravação contínua tem muito mais contexto
  /// melódico pro ACRCloud reconhecer do que várias fatiadas — testado na
  /// prática, precisão caiu de verdade com 3 tentativas menores. A
  /// detecção de silêncio (abaixo) já resolve "não fica esperando à toa"
  /// sem precisar fatiar a gravação.
  int _maxAttemptsFor(ListenMode mode) => mode == ListenMode.hum ? 1 : 5;

  // Detecção de silêncio — só no modo Cantar: se a pessoa já começou a
  // cantar e depois fica muda por 5s seguidos, entende que ela terminou e
  // corta a gravação na hora.
  //
  // "Voz" e "silêncio" NÃO são um número fixo de amplitude — testado na
  // prática (14/ago/2026), um piso fixo (0.15) não generaliza: em ambiente
  // barulhento o ruído de fundo nunca cai abaixo dele (silêncio nunca
  // dispara), e em ambiente muito quieto qualquer sopro passaria como
  // "voz". Em vez disso, cada gravação calibra sozinha o piso de ruído do
  // próprio ambiente, e "voz"/"silêncio" são definidos como margens ACIMA
  // desse piso — o que importa é o CONTRASTE entre a voz da pessoa e o
  // fundo, não um volume absoluto.
  // Testado na prática (14/ago/2026, 2ª rodada): usuário confirmou ter
  // parado de cantar de vez e ficado calado, mas mesmo assim o maior
  // trecho contínuo abaixo do piso de voz foi só 1300ms (interrompido 8x
  // em ~37s) — algum ruído periódico do ambiente (ventilador, trânsito,
  // ar-condicionado etc.) cruzava o piso de voz a cada poucos segundos e
  // resetava a contagem. Margem e debounce abaixo aumentados a partir
  // desse dado real, não chute.
  static const _voiceMargin = 0.18; // acima do piso de ruído pra contar como "cantando" (era 0.12)
  // O piso desce imediatamente ao ouvir algo mais quieto que ele (silêncio
  // de verdade nunca é "ruído", então é seguro confiar na hora), mas só
  // sobe bem devagar com o tempo — caso o ambiente realmente fique mais
  // barulhento no meio da gravação (carro passando, tv ligada por perto).
  // Sem esse teto de subida, um pico alto isolado não empurra o piso (ele
  // só reage a amostras MAIS BAIXAS que o piso atual, nunca mais altas).
  static const _noiseFloorDecayPerSecond = 0.003;
  // Ignora picos de ruído (respiração, tosse, clique, ruído ambiente
  // periódico) que cruzam o piso de voz sem a pessoa ter realmente voltado
  // a cantar — só reseta a contagem de silêncio se o som acima do piso
  // persistir por esse tempo mínimo. 400ms não foi suficiente (ver acima);
  // 1500ms dá folga confortável sobre os 1300ms observados, mantendo
  // margem segura abaixo de qualquer frase cantada de verdade (sempre bem
  // mais longa que isso).
  static const _voiceResumeDebounce = Duration(milliseconds: 1500);
  static const _silenceDurationToStop = Duration(seconds: 5);

  double _noiseFloor = 0.0;
  DateTime _noiseFloorUpdatedAt = DateTime.now();
  bool _hasDetectedVoice = false;
  DateTime? _silenceStartedAt;
  DateTime? _voiceResumedAt;

  // TEMPORÁRIO — junto com debugStopReasonProvider acima, só pra
  // diagnóstico (ver comentário lá). Usuário relatou que o auto-stop de 5s
  // de silêncio não disparou (14/ago/2026); o piso fixo virou adaptativo
  // por causa disso — esses campos continuam aqui pra confirmar que o novo
  // piso calibra certo em ambientes diferentes, antes de remover tudo.
  DateTime? _segmentStartedAt;
  double _lastAmplitude = 0;
  double _minAmplitudeSeen = 1.0;
  int _maxContinuousSilenceMs = 0;
  int _silenceInterruptedCount = 0;

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
    _silenceStartedAt = null;
    _voiceResumedAt = null;
    _noiseFloor = 0.0; // recalibra do zero a cada gravação — ambiente pode ter mudado
    _noiseFloorUpdatedAt = DateTime.now();
    _segmentStartedAt = DateTime.now(); // TEMPORÁRIO — só pro diagnóstico
    _minAmplitudeSeen = 1.0; // TEMPORÁRIO
    _maxContinuousSilenceMs = 0; // TEMPORÁRIO
    _silenceInterruptedCount = 0; // TEMPORÁRIO
    _ref.read(debugStopReasonProvider.notifier).state = null; // TEMPORÁRIO
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
        // TEMPORÁRIO — só pro diagnóstico
        _lastAmplitude = amp;
        if (amp < _minAmplitudeSeen) _minAmplitudeSeen = amp;
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
    await Future.any([
      Future.delayed(_segmentDurationFor(mode)),
      stopEarly.future,
    ]);
    // TEMPORÁRIO — se chegou aqui e o sinalizador NÃO foi completado, foi o
    // timer de duração máxima que resolveu a corrida (não silêncio, nem
    // toque manual — esses dois já escrevem o motivo deles antes de
    // completar o sinalizador). Só interessa no Cantar; no Ouvir o
    // sinalizador nunca é usado, sempre "vence" o timer de 4s mesmo.
    if (mode == ListenMode.hum && !stopEarly.isCompleted) {
      final elapsedMs = DateTime.now().difference(_segmentStartedAt!).inMilliseconds;
      _ref.read(debugStopReasonProvider.notifier).state = 'tempo máximo atingido (${elapsedMs}ms, teto '
          '${_segmentDurationFor(mode).inSeconds}s) — silêncio nunca disparou. piso de ruído calibrado '
          '${_noiseFloor.toStringAsFixed(2)}, amp. mín. vista ${_minAmplitudeSeen.toStringAsFixed(2)}, maior '
          'trecho contínuo abaixo do piso de voz ${_maxContinuousSilenceMs}ms, interrompido ${_silenceInterruptedCount}x';
    }
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

    // Recalibra o piso de ruído: desce na hora se ouvir algo mais quieto
    // que o piso atual, sobe só bem devagar com o tempo (ver comentário
    // em _noiseFloorDecayPerSecond).
    if (amplitude <= _noiseFloor) {
      _noiseFloor = amplitude;
      _noiseFloorUpdatedAt = now;
    } else {
      final secondsSinceUpdate = now.difference(_noiseFloorUpdatedAt).inMilliseconds / 1000.0;
      final drifted = (_noiseFloor + _noiseFloorDecayPerSecond * secondsSinceUpdate).clamp(0.0, 1.0);
      if (drifted > _noiseFloor) {
        _noiseFloor = drifted;
        _noiseFloorUpdatedAt = now;
      }
    }

    final voiceThreshold = (_noiseFloor + _voiceMargin).clamp(0.0, 1.0);

    if (amplitude >= voiceThreshold) {
      _hasDetectedVoice = true;
      // Só considera uma retomada de verdade (zera a contagem de
      // silêncio) se isso persistir por um tempo mínimo — um pico curto
      // de ruído não deveria resetar 5s de silêncio já acumulados.
      _voiceResumedAt ??= now;
      if (now.difference(_voiceResumedAt!) >= _voiceResumeDebounce && _silenceStartedAt != null) {
        // TEMPORÁRIO — registra o quanto chegou a acumular antes de zerar.
        final stretchMs = now.difference(_silenceStartedAt!).inMilliseconds;
        if (stretchMs > _maxContinuousSilenceMs) _maxContinuousSilenceMs = stretchMs;
        _silenceInterruptedCount++;
        _silenceStartedAt = null; // retomada real, zera a contagem
      }
      return;
    }
    _voiceResumedAt = null; // não estava (ou não persistiu) acima do piso de voz

    if (!_hasDetectedVoice) return; // silêncio antes de começar, ignora

    // Tudo abaixo do piso de voz conta pra contagem de silêncio — só um
    // som claramente acima do piso E sustentado (ver debounce acima)
    // reseta.
    _silenceStartedAt ??= now;
    final silenceElapsed = now.difference(_silenceStartedAt!);
    if (silenceElapsed.inMilliseconds > _maxContinuousSilenceMs) {
      _maxContinuousSilenceMs = silenceElapsed.inMilliseconds; // TEMPORÁRIO — "recorde" em andamento
    }
    if (silenceElapsed >= _silenceDurationToStop) {
      // TEMPORÁRIO — registra o motivo antes de completar o sinalizador.
      final elapsedMs = _segmentStartedAt != null ? now.difference(_segmentStartedAt!).inMilliseconds : -1;
      _ref.read(debugStopReasonProvider.notifier).state = 'silêncio detectado (${elapsedMs}ms desde o início, '
          'última amplitude ${amplitude.toStringAsFixed(2)}, piso de ruído ${_noiseFloor.toStringAsFixed(2)})';
      stopEarly.complete();
    }
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
      // TEMPORÁRIO — registra o motivo antes de completar o sinalizador.
      final elapsedMs = _segmentStartedAt != null ? DateTime.now().difference(_segmentStartedAt!).inMilliseconds : -1;
      _ref.read(debugStopReasonProvider.notifier).state = 'toque manual (${elapsedMs}ms desde o início, última '
          'amplitude ${_lastAmplitude.toStringAsFixed(2)}, piso de ruído ${_noiseFloor.toStringAsFixed(2)}, mín. '
          'vista ${_minAmplitudeSeen.toStringAsFixed(2)}, maior silêncio contínuo ${_maxContinuousSilenceMs}ms, '
          'interrompido ${_silenceInterruptedCount}x)';
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
    _ref.read(debugStopReasonProvider.notifier).state = null; // TEMPORÁRIO
  }

  void reset() {
    state = ListenState(mode: state.mode);
    _ref.read(debugStopReasonProvider.notifier).state = null; // TEMPORÁRIO
  }
}

final listenControllerProvider = StateNotifierProvider<ListenController, ListenState>((ref) {
  return ListenController(ref.watch(audioRecorderProvider), ref.watch(apiClientProvider), ref);
});
