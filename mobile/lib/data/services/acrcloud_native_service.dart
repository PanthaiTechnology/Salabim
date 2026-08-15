import 'dart:async';

import 'package:flutter/services.dart';

/// Resultado do reconhecimento via SDK on-device do ACRCloud — versão
/// enxuta do que `AcrCloudBridge.kt` (nativo) já filtrou do JSON bruto
/// deles. `null` (via [AcrCloudNativeResult.fromMap]) significa "não
/// achou", igual ao `Track?` do resto do app.
class AcrCloudNativeResult {
  const AcrCloudNativeResult({
    required this.title,
    required this.artist,
    this.album,
    this.isrc,
    this.score,
  });

  final String title;
  final String artist;
  final String? album;
  final String? isrc;
  final double? score;

  static AcrCloudNativeResult? fromMap(Map<dynamic, dynamic> map) {
    final found = map['found'] as bool? ?? false;
    if (!found) return null;
    return AcrCloudNativeResult(
      title: map['title'] as String? ?? 'Desconhecido',
      artist: map['artist'] as String? ?? 'Desconhecido',
      album: map['album'] as String?,
      isrc: map['isrc'] as String?,
      score: (map['score'] as num?)?.toDouble(),
    );
  }
}

/// Ponte pro SDK on-device do ACRCloud — branch de teste (ver
/// ARCHITECTURE.md §4.3/4.4). Wrapper fino do MethodChannel/EventChannel
/// nativos (ver MainActivity.kt/AcrCloudBridge.kt, Android). `recognize()`
/// do SDK deles é "tudo incluso": grava, calcula o fingerprint no próprio
/// aparelho, consulta o servidor, e só chama de volta quando o resultado
/// (achou ou não) está pronto — diferente do pipeline REST atual (várias
/// tentativas, exige 2 concordando), aqui é uma chamada só.
class AcrCloudNativeService {
  static const _methodChannel = MethodChannel('salabim/acrcloud');
  static const _volumeChannel = EventChannel('salabim/acrcloud/volume');

  Completer<AcrCloudNativeResult?>? _pendingRecognition;

  AcrCloudNativeService() {
    _methodChannel.setMethodCallHandler(_handleNativeCall);
  }

  /// Chamadas INICIADAS PELO LADO NATIVO (não são resposta de um
  /// invokeMethod nosso) — hoje só "onResult", disparada quando
  /// AcrCloudBridge.onResult (Kotlin) recebe o callback do SDK.
  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onResult') {
      final map = call.arguments as Map<dynamic, dynamic>;
      final result = AcrCloudNativeResult.fromMap(map);
      final pending = _pendingRecognition;
      _pendingRecognition = null;
      pending?.complete(result);
    }
  }

  /// Stream de amplitude (0.0-1.0).
  ///
  /// BUG encontrado em teste real (15/ago/2026): diferente do pacote
  /// `record` (que manda dBFS negativo, tipo -45 a 0, daí a fórmula
  /// `(raw+45)/45` em audio_recorder_service.dart), o SDK do ACRCloud já
  /// manda o volume PRÉ-NORMALIZADO entre 0.0 e 1.0 (confirmado via log
  /// real: valores tipo 0.63, 0.75, 0.80 durante gravação normal).
  /// Aplicar a mesma fórmula de dBFS num valor que já é ~0.75 dava
  /// (0.75+45)/45 ≈ 1.02, saturando em 1.0 sempre — por isso a animação
  /// da onda sonora ficava travada no máximo o tempo todo no modo Ouvir
  /// (nativo), diferente da animação do Cantar (que usa `record`, com a
  /// fórmula certa pra ela). Aqui só precisa do clamp, sem a fórmula de
  /// dBFS.
  Stream<double> get volume => _volumeChannel.receiveBroadcastStream().map((v) {
        final raw = (v as num).toDouble();
        return raw.clamp(0.0, 1.0);
      });

  Future<bool> init({required String host, required String accessKey, required String accessSecret}) async {
    final result = await _methodChannel.invokeMethod<bool>('init', {
      'host': host,
      'accessKey': accessKey,
      'accessSecret': accessSecret,
    });
    return result ?? false;
  }

  /// Dispara o reconhecimento e espera o resultado — o SDK decide sozinho
  /// quanto tempo gravar antes de responder (não temos o controle fino de
  /// checkpoints que construímos pro caminho REST). Retorna `null` se não
  /// achou, ou se não conseguiu nem começar a gravar.
  Future<AcrCloudNativeResult?> recognize() async {
    final completer = Completer<AcrCloudNativeResult?>();
    _pendingRecognition = completer;

    final started = await _methodChannel.invokeMethod<bool>('startRecognize') ?? false;
    if (!started) {
      _pendingRecognition = null;
      return null;
    }

    return completer.future;
  }

  /// Cancela um reconhecimento em andamento (toque manual do usuário).
  Future<void> cancel() async {
    final pending = _pendingRecognition;
    _pendingRecognition = null;
    if (pending != null && !pending.isCompleted) {
      pending.complete(null);
    }
    await _methodChannel.invokeMethod('cancel');
  }

  /// Libera o cliente nativo — chamar quando o app não vai mais precisar
  /// do reconhecimento nativo nessa sessão (ex: dispose do provider).
  Future<void> release() async {
    await _methodChannel.invokeMethod('release');
  }
}
