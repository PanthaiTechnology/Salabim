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

  // Credenciais do SDK on-device do ACRCloud — branch de teste (ver
  // ARCHITECTURE.md §4.3/4.4). Mesmo projeto/chave já usado pelo Cantar
  // via REST (acrcloud_client.py no backend) — não é secreto de verdade
  // no sentido estrito (fica embutido no APK, extraível por quem
  // decompilar), mas passar via --dart-define em vez de hardcoded no
  // fonte evita deixar a chave craquestada direto no código versionado.
  static const String acrCloudHost = String.fromEnvironment(
    'ACRCLOUD_HOST',
    defaultValue: 'identify-us-west-2.acrcloud.com',
  );
  static const String acrCloudAccessKey = String.fromEnvironment('ACRCLOUD_ACCESS_KEY');
  static const String acrCloudAccessSecret = String.fromEnvironment('ACRCLOUD_ACCESS_SECRET');
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
