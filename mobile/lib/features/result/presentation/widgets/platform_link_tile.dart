import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../data/models/track.dart';

/// Um botão por plataforma de streaming (Spotify, Apple Music, Deezer, Tidal,
/// YouTube Music...), populado pelos links que o backend resolve via Odesli.
class PlatformLinkTile extends StatelessWidget {
  const PlatformLinkTile({super.key, required this.link});

  final PlatformLink link;

  static const _icons = <String, IconData>{
    'spotify': Icons.podcasts_rounded,
    'apple_music': Icons.apple_rounded,
    'deezer': Icons.album_rounded,
    'tidal': Icons.waves_rounded,
    'youtube_music': Icons.smart_display_rounded,
    'youtube': Icons.play_circle_fill_rounded,
    'amazon_music': Icons.shopping_bag_rounded,
    'soundcloud': Icons.cloud_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final platform = StreamingPlatform.fromKey(link.platform);
    final label = platform?.label ?? link.platform;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ListTile(
        leading: Icon(_icons[link.platform] ?? Icons.link_rounded, color: AppColors.primary),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        trailing: const Icon(Icons.open_in_new_rounded, size: 18, color: AppColors.textSecondary),
        onTap: () => launchUrl(Uri.parse(link.url), mode: LaunchMode.externalApplication),
      ),
    );
  }
}
