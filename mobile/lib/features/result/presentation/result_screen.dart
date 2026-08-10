import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../../../core/theme/app_theme.dart';
import '../../../data/models/track.dart';
import '../../../data/services/history_service.dart';
import 'widgets/platform_link_tile.dart';
import 'widgets/preview_play_button.dart';

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
  bool _previewLoaded = false;
  Duration _previewPosition = Duration.zero;
  Duration? _previewDuration;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _playerStateSub;

  @override
  void initState() {
    super.initState();
    unawaited(_historyService.addEntry(widget.track, widget.track.matchedProvider));

    // Assinado uma única vez pra vida da tela — assinar de novo a cada play
    // (como era antes) ia empilhando listeners duplicados a cada toque.
    _positionSub = _player.positionStream.listen((position) {
      if (mounted) setState(() => _previewPosition = position);
    });
    _durationSub = _player.durationStream.listen((duration) {
      if (mounted) setState(() => _previewDuration = duration);
    });
    _playerStateSub = _player.playerStateStream.listen((playerState) async {
      if (!mounted) return;
      if (playerState.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
        setState(() {
          _isPlayingPreview = false;
          _previewPosition = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playerStateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePreview() async {
    final previewUrl = widget.track.previewUrl;
    if (previewUrl == null) return;

    if (_isPlayingPreview) {
      setState(() => _isPlayingPreview = false);
      await _player.pause();
      return;
    }

    try {
      // Só carrega a URL na primeira vez — despausar depois disso continua
      // de onde parou, em vez de recomeçar o preview do zero.
      if (!_previewLoaded) {
        await _player.setUrl(previewUrl);
        _previewLoaded = true;
      }
      // NÃO espera o play() aqui: no just_audio, o Future de play() só
      // resolve quando a reprodução PARA (pausa/termina), não quando
      // começa. Se esperássemos, o ícone só trocaria pra barrinhas no
      // toque seguinte — atualiza a UI na hora e deixa o play() rodando
      // por baixo.
      setState(() => _isPlayingPreview = true);
      unawaited(_player.play().catchError((_) {}));
    } catch (_) {
      // Sem preview disponível para essa faixa — ok, os links de plataforma continuam funcionando.
      if (mounted) setState(() => _isPlayingPreview = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.track;
    final durationMs = _previewDuration?.inMilliseconds ?? 0;
    final progress = durationMs > 0 ? _previewPosition.inMilliseconds / durationMs : 0.0;

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
              PreviewPlayButton(
                isPlaying: _isPlayingPreview,
                progress: progress,
                onTap: _togglePreview,
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
