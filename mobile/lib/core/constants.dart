/// Constantes globais do app.
class AppConstants {
  AppConstants._();

  /// Base URL do backend. Trocar por variável de ambiente/flavor em produção
  /// (--dart-define=API_BASE_URL=https://api.salabim.app).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000', // 10.0.2.2 = localhost do host no emulador Android
  );

  static const int maxRecordingSeconds = 12;
  static const int minRecordingSeconds = 3;
}

enum StreamingPlatform {
  spotify('spotify', 'Spotify'),
  appleMusic('apple_music', 'Apple Music'),
  deezer('deezer', 'Deezer'),
  tidal('tidal', 'Tidal'),
  youtubeMusic('youtube_music', 'YouTube Music'),
  youtube('youtube', 'YouTube'),
  amazonMusic('amazon_music', 'Amazon Music'),
  soundcloud('soundcloud', 'SoundCloud');

  const StreamingPlatform(this.key, this.label);
  final String key;
  final String label;

  static StreamingPlatform? fromKey(String key) {
    for (final platform in StreamingPlatform.values) {
      if (platform.key == key) return platform;
    }
    return null;
  }
}
