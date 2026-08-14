import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../models/track.dart';

class MicPermissionDeniedException implements Exception {
  @override
  String toString() => 'Permissão de microfone negada';
}

/// Devolvido por [AudioRecorderService.startListenStream]: um stream de
/// amplitude (pra UI) e um stream de snapshots em WAV (um por checkpoint de
/// duração acumulada atingido), os dois vindos da MESMA gravação contínua —
/// ver o método pra detalhes.
class ListenStreamHandle {
  ListenStreamHandle({required this.amplitude, required this.checkpoints, required this.stop});

  final Stream<double> amplitude;
  final Stream<Uint8List> checkpoints;

  /// Encerra a gravação real na hora, mesmo que ainda falte checkpoint —
  /// idempotente (seguro chamar mais de uma vez).
  final Future<void> Function() stop;
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

  /// Grava em arquivo (finaliza ao chamar [stopRecording]) e retorna um
  /// stream de amplitude (0.0-1.0) para animar a onda sonora na tela de
  /// escuta. Usado só pelo modo Cantar agora — Ouvir usa
  /// [startListenStream] (ver ARCHITECTURE.md §4.3: gravações separadas
  /// coladas degradam o reconhecimento; stream contínuo evita isso).
  ///
  /// Cantar usa wav (sem perdas) — o reconhecimento de melodia é mais
  /// sensível a artefatos de compressão do que o fingerprint de áudio
  /// normal, então vale o arquivo maior.
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
    // web; no app mobile de verdade quem chama esse método é só o Cantar.
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
        // Teste com AndroidAudioSource.camcorder pro modo Ouvir (14/ago/2026,
        // ver histórico do git) — revertido: usuário testou no aparelho
        // real e piorou. Voltou pra fonte padrão (mesmo comportamento de
        // antes de qualquer teste de captura).
        androidConfig: const AndroidRecordConfig(),
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

  static const _sampleRate = 44100;
  static const _numChannels = 1;
  static const _bitsPerSample = 16;
  static const _bytesPerSecond = _sampleRate * _numChannels * _bitsPerSample ~/ 8;

  /// Ouvir: grava em stream contínuo de PCM 16-bit bruto — o microfone
  /// NUNCA para/reinicia entre checagens (ver ARCHITECTURE.md §4.3:
  /// gravações separadas coladas degradam o reconhecimento de forma
  /// mensurável; stream contínuo não tem esse problema, comprovado em
  /// teste). [checkpoints] são durações crescentes (ex: 4s, 8s, 18s) — a
  /// cada uma atingida, emite pelo `checkpoints` do handle um WAV válido e
  /// completo (cabeçalho próprio) com TODO o áudio gravado até ali, sem
  /// cortar/pausar a gravação real, que continua intacta rumo ao próximo
  /// checkpoint. Encerra sozinho depois do último checkpoint, ou antes
  /// disso se [ListenStreamHandle.stop] for chamado.
  ListenStreamHandle startListenStream({required List<Duration> checkpoints}) {
    final amplitudeController = StreamController<double>.broadcast();
    final checkpointController = StreamController<Uint8List>();
    final buffer = BytesBuilder(copy: false);
    var nextCheckpointIndex = 0;
    var stopped = false;
    StreamSubscription<Uint8List>? pcmSub;
    StreamSubscription<Amplitude>? ampSub;

    Future<void> stopInternal() async {
      if (stopped) return;
      stopped = true;
      await pcmSub?.cancel();
      await ampSub?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {
        // Sem stream/gravação ativa pra parar — inofensivo, só encerrando.
      }
      if (!checkpointController.isClosed) await checkpointController.close();
      if (!amplitudeController.isClosed) await amplitudeController.close();
    }

    Future<void> begin() async {
      if (!await hasPermission()) {
        checkpointController.addError(MicPermissionDeniedException());
        await stopInternal();
        return;
      }

      final Stream<Uint8List> pcmStream;
      try {
        pcmStream = await _recorder.startStream(
          const RecordConfig(
            encoder: AudioEncoder.pcm16bits,
            sampleRate: _sampleRate,
            numChannels: _numChannels,
            androidConfig: AndroidRecordConfig(),
          ),
        );
      } catch (e) {
        checkpointController.addError(e);
        await stopInternal();
        return;
      }
      if (stopped) return; // cancelado enquanto o startStream ainda resolvia

      ampSub = _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amp) {
        if (amplitudeController.isClosed) return;
        final normalized = ((amp.current + 45) / 45).clamp(0.0, 1.0);
        amplitudeController.add(normalized);
      });

      pcmSub = pcmStream.listen(
        (chunk) {
          if (stopped) return;
          buffer.add(chunk);
          final elapsedMs = (buffer.length / _bytesPerSecond * 1000).round();
          while (nextCheckpointIndex < checkpoints.length &&
              elapsedMs >= checkpoints[nextCheckpointIndex].inMilliseconds) {
            final wav = _wrapPcmAsWav(buffer.toBytes());
            if (!checkpointController.isClosed) checkpointController.add(wav);
            nextCheckpointIndex++;
          }
          if (nextCheckpointIndex >= checkpoints.length) {
            unawaited(stopInternal());
          }
        },
        onError: (Object e) {
          if (!checkpointController.isClosed) checkpointController.addError(e);
          unawaited(stopInternal());
        },
        onDone: () {
          unawaited(stopInternal());
        },
      );
    }

    unawaited(begin());

    return ListenStreamHandle(
      amplitude: amplitudeController.stream,
      checkpoints: checkpointController.stream,
      stop: stopInternal,
    );
  }

  /// Monta um arquivo WAV (PCM 16-bit, mono, 44.1kHz) completo e válido a
  /// partir de bytes de PCM bruto — o cabeçalho é escrito na mão porque não
  /// existe finalização de arquivo real aqui (a gravação real segue
  /// intacta, isso é só um "retrato" do que já foi capturado até agora).
  static Uint8List _wrapPcmAsWav(Uint8List pcm) {
    const byteRate = _bytesPerSecond;
    const blockAlign = _numChannels * _bitsPerSample ~/ 8;
    final dataLength = pcm.length;

    final header = BytesBuilder();
    void writeAscii(String s) => header.add(s.codeUnits);
    void writeUint32(int v) => header.add([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
    void writeUint16(int v) => header.add([v & 0xFF, (v >> 8) & 0xFF]);

    writeAscii('RIFF');
    writeUint32(36 + dataLength);
    writeAscii('WAVE');
    writeAscii('fmt ');
    writeUint32(16); // tamanho do bloco fmt
    writeUint16(1); // PCM
    writeUint16(_numChannels);
    writeUint32(_sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(_bitsPerSample);
    writeAscii('data');
    writeUint32(dataLength);

    final out = BytesBuilder();
    out.add(header.toBytes());
    out.add(pcm);
    return out.toBytes();
  }

  void dispose() {
    _amplitudeSub?.cancel();
    _recorder.dispose();
  }
}
