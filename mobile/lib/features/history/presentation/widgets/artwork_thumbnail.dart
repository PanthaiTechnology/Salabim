import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Miniatura quadrada com cantos arredondados pra capa de álbum na lista de
/// histórico — cai num ícone com gradiente da marca quando não tem capa.
class ArtworkThumbnail extends StatelessWidget {
  const ArtworkThumbnail({super.key, required this.url, this.size = 52});

  final String? url;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url != null
          ? CachedNetworkImage(
              imageUrl: url!,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => _placeholder(),
              errorWidget: (_, __, ___) => _placeholder(),
            )
          : _placeholder(),
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(gradient: AppColors.listenGradient),
      child: Icon(Icons.music_note_rounded, color: Colors.white, size: size * 0.45),
    );
  }
}
