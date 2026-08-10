import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/history_service.dart';
import 'widgets/platform_link_tile.dart';

/// Tela de resultado — igual em espírito à do Shazam: capa, título, artista,
/// player de preview de alguns segundos (SEMPRE via URL oficial do provedor,
/// nunca um recorte próprio — ver ARCHITECTURE.md §10) e botões para abrir a
/// faixa direto em cada plataforma de streaming.
///
/// Toda vez que essa tela abre, a música é salva no histórico local do
/// aparelho (ver HistoryService) — cobre tanto o resultado de Ouvir/Cantarolar
/// quanto o de busca por texto, já que ambos chegam aqui do mesmo jeito.
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.track});

  final Track track;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  final _player = AudioPlayer();
  final _historyService = HistoryService();
  bool _isPlayingPreview = false;

  @override
  void initState() {
    super.initState();
    unawaited(_historyService.addEntry(widget.track, widget.track.matchedProvider));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    final previewUrl = widget.track.previewUrl;
    if (previewUrl == null) return;

    if (_isPlayingPreview) {
      await _player.pause();
      setState(() => _isPlayingPreview = false);
      return;
    }

    try {
      await _player.setUrl(previewUrl);
      await _player.play();
      setState(() => _isPlayingPreview = true);
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed && mounted) {
          setState(() => _isPlayingPreview = false);
        }
      });
    } catch (_) {
      // Sem preview disponível para essa faixa — ok, os links de plataforma continuam funcionando.
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: track.artworkUrl != null
                  ? CachedNetworkImage(
                      imageUrl: track.artworkUrl!,
                      width: 240,
                      height: 240,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => _artworkPlaceholder(),
                      errorWidget: (_, __, ___) => _artworkPlaceholder(),
                    )
                  : _artworkPlaceholder(),
            ),
            const SizedBox(height: 24),
            Text(track.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(track.artist, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: AppColors.textSecondary)),
            if (track.album != null) ...[
              const SizedBox(height: 2),
              Text(track.album!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
            const SizedBox(height: 20),
            if (track.previewUrl != null)
              ElevatedButton.icon(
                onPressed: _togglePreview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                icon: Icon(_isPlayingPreview ? Icons.pause_rounded : Icons.play_arrow_rounded),
                label: Text(_isPlayingPreview ? 'Pausar prévia' : 'Ouvir prévia'),
              ),
            const SizedBox(height: 28),
            if (track.platformLinks.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Ouvir em:', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              const SizedBox(height: 8),
              ...track.platformLinks.map((link) => PlatformLinkTile(link: link)),
            ] else
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Ainda não encontramos links de streaming para essa faixa.',
                  style: TextStyle(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _artworkPlaceholder() {
    return Container(
      width: 240,
      height: 240,
      decoration: BoxDecoration(gradient: AppColors.listenGradient, borderRadius: BorderRadius.circular(24)),
      child: const Icon(Icons.music_note_rounded, size: 80, color: Colors.white),
    );
  }
}
