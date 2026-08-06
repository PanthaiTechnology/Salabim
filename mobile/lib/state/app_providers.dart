import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/track.dart';
import '../data/services/api_client.dart';
import '../data/services/audio_recorder_service.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());

final audioRecorderProvider = Provider<AudioRecorderService>((ref) {
  final service = AudioRecorderService();
  ref.onDispose(service.dispose);
  return service;
});

/// Estado da tela de escuta: idle -> recording -> identifying -> result/error.
enum ListenStatus { idle, recording, identifying, notFound, error }

class ListenState {
  final ListenStatus status;
  final ListenMode mode;
  final double amplitude;
  final String? errorMessage;
  final Track? result;

  const ListenState({
    this.status = ListenStatus.idle,
    this.mode = ListenMode.listen,
    this.amplitude = 0.0,
    this.errorMessage,
    this.result,
  });

  ListenState copyWith({
    ListenStatus? status,
    ListenMode? mode,
    double? amplitude,
    String? errorMessage,
    Track? result,
  }) {
    return ListenState(
      status: status ?? this.status,
      mode: mode ?? this.mode,
      amplitude: amplitude ?? this.amplitude,
      errorMessage: errorMessage,
      result: result ?? this.result,
    );
  }
}

class ListenController extends StateNotifier<ListenState> {
  ListenController(this._recorder, this._api) : super(const ListenState());

  final AudioRecorderService _recorder;
  final ApiClient _api;

  void setMode(ListenMode mode) {
    if (state.status == ListenStatus.recording) return;
    state = state.copyWith(mode: mode);
  }

  Future<void> startListening() async {
    state = state.copyWith(status: ListenStatus.recording, errorMessage: null, result: null);
    _recorder.startRecording().listen(
      (amp) => state = state.copyWith(amplitude: amp),
      onError: (_) {
        state = state.copyWith(
          status: ListenStatus.error,
          errorMessage: 'Precisamos da permissão do microfone para identificar a música.',
        );
      },
    );
  }

  Future<void> stopAndIdentify() async {
    final file = await _recorder.stopRecording();
    if (file == null) {
      state = state.copyWith(status: ListenStatus.idle);
      return;
    }
    state = state.copyWith(status: ListenStatus.identifying);
    try {
      final track = await _api.identify(audioFile: file, mode: state.mode);
      if (track == null) {
        state = state.copyWith(status: ListenStatus.notFound);
      } else {
        state = state.copyWith(status: ListenStatus.idle, result: track);
      }
    } on IdentifyException catch (e) {
      state = state.copyWith(status: ListenStatus.error, errorMessage: e.message);
    }
  }

  Future<void> cancel() async {
    await _recorder.cancelRecording();
    state = const ListenState();
  }

  void reset() => state = ListenState(mode: state.mode);
}

final listenControllerProvider = StateNotifierProvider<ListenController, ListenState>((ref) {
  return ListenController(ref.watch(audioRecorderProvider), ref.watch(apiClientProvider));
});
