import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/api_client.dart';

/// Busca por trecho de letra ou por descrição livre ("aquela música do
/// comercial dos anos 90...") — o terceiro jeito de achar uma música no Salabim,
/// sem precisar de áudio nenhum.
class TextSearchScreen extends StatefulWidget {
  const TextSearchScreen({super.key});

  @override
  State<TextSearchScreen> createState() => _TextSearchScreenState();
}

class _TextSearchScreenState extends State<TextSearchScreen> {
  final _controller = TextEditingController();
  final _api = ApiClient();
  TextSearchKind _kind = TextSearchKind.lyrics;
  List<Track> _results = [];
  bool _loading = false;
  String? _error;

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.length < 2) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await _api.searchText(query: query, kind: _kind);
      setState(() => _results = results);
    } on IdentifyException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Buscar por texto', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SegmentedButton<TextSearchKind>(
            segments: TextSearchKind.values
                .map((k) => ButtonSegment(value: k, label: Text(k.label)))
                .toList(),
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            onSubmitted: (_) => _search(),
            decoration: InputDecoration(
              hintText: _kind == TextSearchKind.lyrics
                  ? 'Digite um trecho da letra...'
                  : 'Descreva a música (época, clima, contexto)...',
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              suffixIcon: IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search),
            ),
          ),
          const SizedBox(height: 16),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null) Text(_error!, style: const TextStyle(color: AppColors.error)),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final track = _results[index];
                return ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.music_note_rounded)),
                  title: Text(track.title),
                  subtitle: Text(track.artist),
                  onTap: () => context.push('/result', extra: track),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
