import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/track.dart';

class MicPermissionDeniedException implements Exception {
  @override
  String toString() => 'Permissão de microfone negada';
}

/// Encapsula a captura de áudio usada tanto no modo "ouvir" quanto no modo
/// "cantar" — a UI só muda o rótulo e o provedor chamado depois.
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Amplitude>? _amplitudeSub;

  Future<bool> hasPermission() async {
    final status = await Permission.microphone.status;
    if (status.isGranted) return true;
    final result = await Permission.microphone.request();
    return result.isGranted;
  }

  /// Inicia a gravação e retorna um stream de amplitude (0.0-1.0) para animar
  /// a onda sonora na tela de escuta.
  ///
  /// [mode] decide o codec: "Ouvir" usa aacLc (comprimido, já validado
  /// ponta a ponta contra a AudD). "Cantar" usa wav (sem perdas) — o
  /// reconhecimento de melodia é mais sensível a artefatos de compressão do
  /// que o fingerprint de áudio normal, então vale o arquivo maior.
  Stream<double> startRecording({required ListenMode mode}) {
    final controller = StreamController<double>();
    _start(controller, mode);
    return controller.stream;
  }

  Future<void> _start(StreamController<double> controller, ListenMode mode) async {
    if (!await hasPermission()) {
      controller.addError(MicPermissionDeniedException());
      await controller.close();
      return;
    }

    // No navegador o suporte a aacLc é incerto entre browsers — wav tem
    // suporte garantido no pacote `record` para Web. Isso só afeta a demo
    // web; no app mobile de verdade a escolha é só por modo (ver acima).
    final useWav = kIsWeb || mode == ListenMode.hum;

    final dir = kIsWeb ? null : await getTemporaryDirectory();
    final extension = useWav ? 'wav' : 'm4a';
    final path = kIsWeb
        ? 'salabim_${DateTime.now().millisecondsSinceEpoch}.$extension'
        : '${dir!.path}/salabim_${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _recorder.start(
      RecordConfig(
        encoder: useWav ? AudioEncoder.wav : AudioEncoder.aacLc,
        sampleRate: 44100,
        numChannels: 1,
      ),
      path: path,
    );

    _amplitudeSub = _recorder
        .onAmplitudeChanged(const Duration(milliseconds: 100))
        .listen((amp) {
      // amp.current vem em dBFS negativo; normaliza para 0.0-1.0
      final normalized = ((amp.current + 45) / 45).clamp(0.0, 1.0);
      controller.add(normalized);
    });
  }

  Future<File?> stopRecording() async {
    await _amplitudeSub?.cancel();
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
  }

  Future<void> cancelRecording() async {
    await _amplitudeSub?.cancel();
    await _recorder.cancel();
  }

  void dispose() {
    _amplitudeSub?.cancel();
    _recorder.dispose();
  }
}
