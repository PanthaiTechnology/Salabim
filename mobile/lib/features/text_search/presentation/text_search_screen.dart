import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:just_audio/just_audio.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/api_client.dart';
import '../../history/presentation/widgets/artwork_thumbnail.dart';
import '../../result/presentation/widgets/preview_play_button.dart';

/// Busca por trecho de letra ou por descrição livre ("aquela música do
/// comercial dos anos 90...") — o terceiro jeito de achar uma música no Salabim,
/// sem precisar de áudio nenhum. Tem um microfone de ditado ao lado da lupa
/// pra quem preferir falar em vez de digitar, e cada resultado mostra a
/// capa real + um botão de preview (mesmo visual das telas de Ouvir/Cantar).
class TextSearchScreen extends StatefulWidget {
  const TextSearchScreen({super.key});

  @override
  State<TextSearchScreen> createState() => _TextSearchScreenState();
}

class _TextSearchScreenState extends State<TextSearchScreen> {
  final _controller = TextEditingController();
  final _api = ApiClient();
  final _speech = stt.SpeechToText();
  final _player = AudioPlayer();

  TextSearchKind _kind = TextSearchKind.lyrics;
  List<Track> _results = [];
  bool _loading = false;
  bool _listening = false;
  bool _speechAvailable = false;
  String? _error;

  // Só uma prévia toca por vez na lista — controlado aqui em vez de por
  // item, pra trocar de faixa automaticamente parar a anterior.
  String? _playingTrackId;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    // Só pra saber quando mostrar/esconder o botão de limpar (o "x" só faz
    // sentido aparecer quando tem algo digitado pra limpar).
    _controller.addListener(() {
      if (mounted) setState(() {});
    });

    _player.positionStream.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.durationStream.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.playerStateStream.listen((s) async {
      if (!mounted) return;
      if (s.processingState == ProcessingState.completed) {
        await _player.stop();
        setState(() {
          _playingTrackId = null;
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });
  }

  Future<void> _initSpeech() async {
    // initialize() já cuida de pedir a permissão de microfone internamente.
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _listening = false);
        }
      },
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
    );
    if (mounted) setState(() => _speechAvailable = available);
  }

  Future<void> _toggleDictation() async {
    if (_listening) {
      await _speech.stop();
      setState(() => _listening = false);
      return;
    }

    if (!_speechAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reconhecimento de voz não disponível nesse aparelho.')),
      );
      return;
    }

    setState(() => _listening = true);
    await _speech.listen(
      listenOptions: stt.SpeechListenOptions(localeId: 'pt_BR', partialResults: true),
      onResult: (result) {
        setState(() => _controller.text = result.recognizedWords);
        if (result.finalResult) {
          setState(() => _listening = false);
          _search();
        }
      },
    );
  }

  Future<void> _togglePreview(Track track) async {
    final previewUrl = track.previewUrl;
    if (previewUrl == null) return;

    if (_playingTrackId == track.id) {
      // Mesma faixa já carregada — só alterna play/pause.
      if (_isPlaying) {
        setState(() => _isPlaying = false);
        await _player.pause();
      } else {
        setState(() => _isPlaying = true);
        unawaited(_player.play().catchError((_) {}));
      }
      return;
    }

    // Trocando de faixa: para a anterior e carrega a nova do zero.
    setState(() {
      _playingTrackId = track.id;
      _isPlaying = true;
      _position = Duration.zero;
      _duration = null;
    });
    try {
      await _player.setUrl(previewUrl);
      unawaited(_player.play().catchError((_) {}));
    } catch (_) {
      if (mounted) {
        setState(() {
          _playingTrackId = null;
          _isPlaying = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _speech.stop();
    _player.dispose();
    _controller.dispose();
    super.dispose();
  }

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
              hintText: _listening
                  ? 'Ouvindo...'
                  : (_kind == TextSearchKind.lyrics
                      ? 'Digite um trecho da letra...'
                      : 'Descreva a música (época, clima, contexto)...'),
              filled: true,
              fillColor: AppColors.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      tooltip: 'Limpar',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        setState(() {
                          _controller.clear();
                          _results = [];
                          _error = null;
                        });
                      },
                    ),
                  IconButton(
                    tooltip: _listening ? 'Parar ditado' : 'Falar em vez de digitar',
                    icon: Icon(
                      _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: _listening ? AppColors.secondary : null,
                    ),
                    onPressed: _toggleDictation,
                  ),
                  IconButton(icon: const Icon(Icons.search_rounded), onPressed: _search),
                ],
              ),
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
                final isThisPlaying = _playingTrackId == track.id && _isPlaying;
                final progress = _playingTrackId == track.id && _duration != null && _duration!.inMilliseconds > 0
                    ? _position.inMilliseconds / _duration!.inMilliseconds
                    : 0.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    onTap: () => context.push('/result', extra: track),
                    leading: ArtworkThumbnail(url: track.artworkUrl),
                    title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: track.previewUrl != null
                        ? PreviewPlayButton(
                            size: 44,
                            isPlaying: isThisPlaying,
                            progress: progress,
                            onTap: () => _togglePreview(track),
                          )
                        : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
