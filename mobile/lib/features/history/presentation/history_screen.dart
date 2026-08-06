import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/api_client.dart';

/// Histórico de músicas já identificadas. Requer usuário autenticado
/// (backend/app/api/routes_history.py) — token gerenciado via shared_preferences.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _api = ApiClient();
  List<Track> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // TODO: recuperar token real de shared_preferences após implementar login.
    final items = await _api.getHistory(token: '');
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_items.isEmpty) {
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (context, index) {
        final track = _items[index];
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
          title: Text(track.title),
          subtitle: Text(track.artist),
          onTap: () => context.push('/result', extra: track),
        );
      },
    );
  }
}
