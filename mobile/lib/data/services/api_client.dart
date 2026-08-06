import 'dart:io';

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
              receiveTimeout: const Duration(seconds: 20),
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
