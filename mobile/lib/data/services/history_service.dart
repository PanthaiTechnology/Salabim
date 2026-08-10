import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';

/// Histórico de músicas identificadas, salvo direto no aparelho — não exige
/// login/conta (o backend tem uma rota de histórico por usuário autenticado,
/// mas o app ainda não implementa login; local é o que garante que toda
/// busca fica salva desde já, igual ao comportamento esperado de um app
/// tipo Shazam). Quando o login existir, dá pra sincronizar este histórico
/// local com o do servidor sem perder nada.
class HistoryService {
  static const _storageKey = 'salabim_history_v1';
  static const _maxEntries = 200;

  Future<List<HistoryEntry>> getHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Histórico corrompido (ex: versão antiga incompatível) — melhor
      // começar limpo do que quebrar o app.
      return [];
    }
  }

  Future<void> addEntry(Track track, String mode) async {
    final entries = await getHistory();

    // Evita duplicar a mesma música gravada em sequência (comum quando a
    // busca em tempo real bate em mais de um segmento seguido).
    entries.removeWhere((e) => e.track.id == track.id);

    entries.insert(0, HistoryEntry(track: track, mode: mode, searchedAt: DateTime.now()));

    final capped = entries.length > _maxEntries ? entries.sublist(0, _maxEntries) : entries;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(capped.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
