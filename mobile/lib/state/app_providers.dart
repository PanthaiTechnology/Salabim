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

  const ListenState({
    this.status = ListenStatus.idle,
    this.mode = ListenMode.listen,
    this.amplitude = 0.0,
    this.attempt = 0,
    this.errorMessage,
    this.result,
  });

  ListenState copyWith({
    ListenStatus? status,
    ListenMode? mode,
    double? amplitude,
    int? attempt,
    String? errorMessage,
    Track? result,
  }) {
    return ListenState(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      amplitude: amplitude ?? this.amplitude,
      attempt: attempt ?? this.attempt,
      errorMessage: errorMessage,
      result: result ?? this.result,
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

  /// Duração de cada trecho gravado e enviado pro backend. Fingerprint de
  /// áudio (Ouvir/AudD) funciona bem com pouco tempo; reconhecimento de
  /// melodia cantada (Cantar/ACRCloud) precisa de mais contexto pra extrair
  /// um contorno melódico confiável — por isso os modos têm durações
  /// diferentes, em vez de um valor único pros dois.
  Duration _segmentDurationFor(ListenMode mode) =>
      mode == ListenMode.hum ? const Duration(seconds: 15) : const Duration(seconds: 4);

  /// Quantos trechos tenta no total antes de desistir. No modo Cantar é só
  /// 1 tentativa: cortar em pedaços (parar e recomeçar gravação) quebra a
  /// continuidade da melodia cantada bem no meio, o que prejudica a
  /// precisão — melhor uma gravação única e contínua (igual recomenda o
  /// próprio Hum to Search do Google) do que várias fatiadas.
  int _maxAttemptsFor(ListenMode mode) => mode == ListenMode.hum ? 1 : 5;

  StreamSubscription<double>? _amplitudeSub;
  bool _sessionActive = false;

  void setMode(ListenMode mode) {
    if (state.status == ListenStatus.recording) return;
    state = state.copyWith(mode: mode);
  }

  /// Único ponto de entrada: um toque começa a escuta contínua. Não existe
  /// um segundo toque "obrigatório" pra buscar — a busca já acontece
  /// automaticamente a cada segmento gravado.
  Future<void> startListening() async {
    _sessionActive = true;
    state = state.copyWith(
      status: ListenStatus.recording,
      errorMessage: null,
      result: null,
      attempt: 0,
    );
    await _recordAndSearchSegment();
  }

  Future<void> _recordAndSearchSegment() async {
    if (!_sessionActive) return;

    await _amplitudeSub?.cancel();
    _amplitudeSub = _recorder.startRecording(mode: state.mode).listen(
      (amp) {
        if (_sessionActive) state = state.copyWith(amplitude: amp);
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
    await Future.delayed(_segmentDurationFor(mode));
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
    }

    if (file == null) return;

    try {
      final track = await _api.identify(audioFile: file, mode: state.mode);
      if (!_sessionActive) return; // já achou em outro segmento ou foi cancelado

      if (track != null) {
        _sessionActive = false;
        await _amplitudeSub?.cancel();
        await _recorder.cancelRecording(); // encerra o próximo trecho já em andamento
        state = state.copyWith(status: ListenStatus.idle, result: track);
        return;
      }
    } on IdentifyException catch (e) {
      if (!_sessionActive) return;
      _sessionActive = false;
      await _amplitudeSub?.cancel();
      await _recorder.cancelRecording();
      state = state.copyWith(status: ListenStatus.error, errorMessage: e.message);
      return;
    }

    // Esse trecho não bateu. Se não há mais tentativas agendadas, desiste.
    if (_sessionActive && !hasMoreAttempts) {
      _sessionActive = false;
      await _amplitudeSub?.cancel();
      state = state.copyWith(status: ListenStatus.notFound);
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

  void reset() => state = ListenState(mode: state.mode);
}

final listenControllerProvider = StateNotifierProvider<ListenController, ListenState>((ref) {
  return ListenController(ref.watch(audioRecorderProvider), ref.watch(apiClientProvider));
});
