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
  // cantar e depois fica muda por 5s seguidos (antes era 3s — aumentado a
  // pedido do usuário pra dar mais margem a pausas naturais entre trechos
  // da música, já que agora não existe mais um teto de tempo "normal"
  // cortando a gravação), entende que ela terminou e corta a gravação na
  // hora. Igual um humano perceberia "ah, ela parou". Amplitude
  // normalizada 0.0-1.0 (ver AudioRecorderService) — 0.15 é um piso
  // conservador acima de ruído ambiente comum de quarto/rua, sem exigir
  // volume alto.
  static const _silenceAmplitudeThreshold = 0.15;
  static const _silenceDurationToStop = Duration(seconds: 5);

  bool _hasDetectedVoice = false;
  DateTime? _silenceStartedAt;

  // TEMPORÁRIO — junto com debugStopReasonProvider acima, só pra
  // diagnóstico (ver comentário lá). Usuário relatou que o auto-stop de 5s
  // de silêncio não disparou (14/ago/2026) — esses campos extras servem
  // pra ver se a amplitude alguma vez realmente cai abaixo do piso
  // (_silenceAmplitudeThreshold) por tempo suficiente, ou se fica sempre
  // "presa" acima dele (ruído ambiente/AGC do microfone empurrando o piso
  // pra cima) — sem esse dado real do aparelho, ajustar o número às cegas
  // arrisca reintroduzir o corte prematuro que já resolvemos antes.
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
          '${_segmentDurationFor(mode).inSeconds}s) — silêncio nunca disparou. amp. mín. vista '
          '${_minAmplitudeSeen.toStringAsFixed(2)} (piso é $_silenceAmplitudeThreshold), maior trecho contínuo '
          'abaixo do piso ${_maxContinuousSilenceMs}ms, interrompido ${_silenceInterruptedCount}x';
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
  /// no modo Cantar. Só começa a contar silêncio depois que a pessoa já
  /// fez algum som acima do piso — silêncio antes de começar a cantar não
  /// conta (senão cortaria a gravação assim que ela tocasse o botão).
  void _checkForSilence(double amplitude, Completer<void> stopEarly) {
    if (stopEarly.isCompleted) return;

    if (amplitude >= _silenceAmplitudeThreshold) {
      // TEMPORÁRIO — se já estava acumulando silêncio e foi interrompido
      // por um som acima do piso antes de completar os 5s, registra o
      // quanto chegou a acumular (pra saber se estava perto ou longe).
      if (_silenceStartedAt != null) {
        final stretchMs = DateTime.now().difference(_silenceStartedAt!).inMilliseconds;
        if (stretchMs > _maxContinuousSilenceMs) _maxContinuousSilenceMs = stretchMs;
        _silenceInterruptedCount++;
      }
      _hasDetectedVoice = true;
      _silenceStartedAt = null; // ainda fazendo som, zera a contagem
      return;
    }

    if (!_hasDetectedVoice) return; // silêncio antes de começar, ignora

    _silenceStartedAt ??= DateTime.now();
    final silenceElapsed = DateTime.now().difference(_silenceStartedAt!);
    if (silenceElapsed.inMilliseconds > _maxContinuousSilenceMs) {
      _maxContinuousSilenceMs = silenceElapsed.inMilliseconds; // TEMPORÁRIO — "recorde" em andamento
    }
    if (silenceElapsed >= _silenceDurationToStop) {
      // TEMPORÁRIO — registra o motivo antes de completar o sinalizador.
      final elapsedMs = _segmentStartedAt != null ? DateTime.now().difference(_segmentStartedAt!).inMilliseconds : -1;
      _ref.read(debugStopReasonProvider.notifier).state =
          'silêncio detectado (${elapsedMs}ms desde o início, última amplitude ${amplitude.toStringAsFixed(2)})';
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
          'amplitude ${_lastAmplitude.toStringAsFixed(2)}, mín. vista ${_minAmplitudeSeen.toStringAsFixed(2)}, '
          'maior silêncio contínuo ${_maxContinuousSilenceMs}ms, interrompido ${_silenceInterruptedCount}x)';
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
