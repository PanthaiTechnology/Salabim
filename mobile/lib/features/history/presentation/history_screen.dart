import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/history_service.dart';

/// Histórico de músicas já identificadas — salvo localmente no aparelho
/// (ver HistoryService), então funciona desde a primeira busca, sem exigir
/// login/conta. Quando o app tiver autenticação, dá pra sincronizar isso com
/// o histórico do backend sem perder o que já foi salvo localmente.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _historyService = HistoryService();
  List<HistoryEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await _historyService.getHistory();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _loading = false;
    });
  }

  Future<void> _clearHistory() async {
    await _historyService.clear();
    await _load();
  }

  static const _modeLabels = {
    'audd': 'Ouvida',
    'acrcloud': 'Cantarolada',
    'musixmatch': 'Buscada por letra',
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_entries.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'Suas músicas identificadas vão aparecer aqui.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Histórico', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              TextButton(onPressed: _clearHistory, child: const Text('Limpar')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _entries.length,
            itemBuilder: (context, index) {
              final entry = _entries[index];
              final track = entry.track;
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                title: Text(track.title),
                subtitle: Text(
                  '${track.artist} · ${_modeLabels[entry.mode] ?? entry.mode} · '
                  '${DateFormat('dd/MM HH:mm').format(entry.searchedAt)}',
                ),
                onTap: () => context.push('/result', extra: track),
              );
            },
          ),
        ),
      ],
    );
  }
}
