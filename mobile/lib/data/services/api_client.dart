import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../core/constants.dart';
import '../models/track.dart';

class IdentifyException implements Exception {
  final String message;
  IdentifyException(this.message);
  @override
  String toString() => message;
}

/// Cliente HTTP do backend do Salabim.
/// Endpoints espelham backend/app/api/*.py — ver docs/api_contract.md.
class ApiClient {
  ApiClient({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: AppConstants.apiBaseUrl,
              connectTimeout: const Duration(seconds: 10),
              // 75s, não 20s: o backend roda no tier gratuito do Render, que
              // "dorme" depois de 15min sem uso e pode levar até ~60s pra
              // acordar na primeira requisição depois disso — com um timeout
              // curto, toda vez que o servidor tivesse dormindo o app dava
              // erro ANTES dele terminar de acordar (bug real, encontrado em
              // teste: primeira busca depois de um tempo parado sempre
              // falhava com "não foi possível conectar", mesmo o servidor
              // respondendo normalmente segundos depois).
              receiveTimeout: const Duration(seconds: 75),
            ));

  final Dio _dio;

  /// Envia o áudio gravado (ouvir ou cantarolar) para identificação.
  Future<Track?> identify({required File audioFile, required ListenMode mode}) async {
    final formData = FormData.fromMap({
      'mode': mode.apiValue,
      'file': await MultipartFile.fromFile(audioFile.path, filename: 'clip.m4a'),
    });

    try {
      final response = await _dio.post('/v1/identify', data: formData);
      final found = response.data['found'] as bool;
      if (!found) return null;
      return Track.fromJson(response.data['track'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw IdentifyException('Muitas buscas seguidas — espera um instante e tenta de novo.');
      }
      throw IdentifyException('Não foi possível conectar ao Salabim agora. Verifica sua internet.');
    }
  }

  /// Igual [identify], mas manda bytes já em memória em vez de um [File] —
  /// usado pelo Ouvir em stream contínuo (ver AudioRecorderService.
  /// startListenStream): cada checkpoint já chega como um WAV completo em
  /// bytes, sem precisar escrever em disco só pra fazer upload.
  Future<Track?> identifyBytes({
    required Uint8List audioBytes,
    required String filename,
    required ListenMode mode,
  }) async {
    final formData = FormData.fromMap({
      'mode': mode.apiValue,
      'file': MultipartFile.fromBytes(audioBytes, filename: filename),
    });

    try {
      final response = await _dio.post('/v1/identify', data: formData);
      final found = response.data['found'] as bool;
      if (!found) return null;
      return Track.fromJson(response.data['track'] as Map<String, dynamic>);
    } on DioException catch (e) {
      if (e.response?.statusCode == 429) {
        throw IdentifyException('Muitas buscas seguidas — espera um instante e tenta de novo.');
      }
      throw IdentifyException('Não foi possível conectar ao Salabim agora. Verifica sua internet.');
    }
  }

  /// Busca por trecho de letra ou descrição livre da música.
  Future<List<Track>> searchText({required String query, required TextSearchKind kind}) async {
    try {
      final response = await _dio.post('/v1/search/text', data: {
        'query': query,
        'kind': kind.apiValue,
      });
      final results = response.data['results'] as List<dynamic>;
      return results.map((e) => Track.fromJson(e as Map<String, dynamic>)).toList();
    } on DioException {
      throw IdentifyException('Não foi possível buscar agora. Verifica sua internet.');
    }
  }

  /// Busca o detalhe completo de uma faixa pelo ID — usado pra resolver os
  /// links de plataforma "sob demanda" quando o usuário abre um resultado
  /// da busca por texto (a lista de busca não vem com os links prontos de
  /// propósito, pra não gastar a cota do Odesli em bloco pra vários
  /// resultados de uma vez só). Retorna null se não achar (cache expirado
  /// no servidor — o app já tem os dados básicos da faixa mesmo assim).
  Future<Track?> getTrackDetails(String trackId) async {
    try {
      final response = await _dio.get('/v1/tracks/$trackId');
      return Track.fromJson(response.data as Map<String, dynamic>);
    } on DioException {
      return null;
    }
  }

  /// Envia feedback sobre um resultado (certo/errado + nome real, se
  /// informado) — o backend guarda isso e, quando o mesmo erro do modo
  /// Cantar acontecer de novo, aplica a correção automaticamente. Falha
  /// silenciosa: o feedback já fica salvo localmente (HistoryService) mesmo
  /// se o envio pro servidor não funcionar agora.
  Future<void> submitFeedback({
    required String matchedTitle,
    required String matchedArtist,
    required String mode,
    required bool wasCorrect,
    String? correctedTitle,
    String? correctedArtist,
  }) async {
    try {
      await _dio.post('/v1/feedback', data: {
        'matched_title': matchedTitle,
        'matched_artist': matchedArtist,
        'mode': mode,
        'was_correct': wasCorrect,
        'corrected_title': correctedTitle,
        'corrected_artist': correctedArtist,
      });
    } on DioException {
      // Sem sorte agora — o feedback local (HistoryService) já foi salvo,
      // que é o que garante a pessoa ver a correção na própria lista dela.
    }
  }

  /// Histórico por conta no backend — ainda não usado (o app não tem login
  /// implementado). O histórico ativo hoje é local, ver HistoryService. Fica
  /// aqui pronto pra quando existir autenticação de verdade, pra sincronizar
  /// sem precisar reescrever essa parte.
  Future<List<Track>> getHistory({required String token}) async {
    try {
      final response = await _dio.get(
        '/v1/history',
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
      final items = response.data as List<dynamic>;
      return items
          .map((e) => Track.fromJson((e as Map<String, dynamic>)['track'] as Map<String, dynamic>))
          .toList();
    } on DioException {
      return [];
    }
  }
}
