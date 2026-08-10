import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class MicPermissionDeniedException implements Exception {
  @override
  String toString() => 'Permissão de microfone negada';
}

/// Encapsula a captura de áudio usada tanto no modo "ouvir" quanto no modo
/// "cantarolar/assobiar" — a UI só muda o rótulo e o provedor chamado depois.
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
  Stream<double> startRecording() {
    final controller = StreamController<double>();
    _start(controller);
    return controller.stream;
  }

  Future<void> _start(StreamController<double> controller) async {
    if (!await hasPermission()) {
      controller.addError(MicPermissionDeniedException());
      await controller.close();
      return;
    }

    // aacLc é o codec padrão (Android/iOS, já validado ponta a ponta contra a
    // AudD/ACRCloud). No navegador o suporte a aacLc é incerto entre
    // browsers — wav tem suporte garantido no pacote `record` para Web, e é
    // exatamente o mesmo tipo de arquivo que a stream de amplitude precisa
    // pra funcionar de verdade. Isso só afeta a demo web; mobile é idêntico
    // ao original.
    final dir = kIsWeb ? null : await getTemporaryDirectory();
    const extension = kIsWeb ? 'wav' : 'm4a';
    final path = kIsWeb
        ? 'salabim_${DateTime.now().millisecondsSinceEpoch}.$extension'
        : '${dir!.path}/salabim_${DateTime.now().millisecondsSinceEpoch}.$extension';

    await _recorder.start(
      const RecordConfig(
        encoder: kIsWeb ? AudioEncoder.wav : AudioEncoder.aacLc,
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
