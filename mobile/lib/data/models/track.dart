/// Modelos de dados espelhando o contrato do backend (backend/app/models/schemas.py).
class PlatformLink {
  final String platform; // spotify | apple_music | deezer | tidal | youtube_music | ...
  final String url;

  const PlatformLink({required this.platform, required this.url});

  factory PlatformLink.fromJson(Map<String, dynamic> json) => PlatformLink(
        platform: json['platform'] as String,
        url: json['url'] as String,
      );

  Map<String, dynamic> toJson() => {'platform': platform, 'url': url};
}

class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String? isrc;
  final String? releaseDate;
  final String? previewUrl;
  final String matchedProvider; // audd | acrcloud | musixmatch
  final double? matchConfidence;
  final List<PlatformLink> platformLinks;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.matchedProvider,
    this.album,
    this.artworkUrl,
    this.isrc,
    this.releaseDate,
    this.previewUrl,
    this.matchConfidence,
    this.platformLinks = const [],
  });

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String,
        album: json['album'] as String?,
        artworkUrl: json['artwork_url'] as String?,
        isrc: json['isrc'] as String?,
        releaseDate: json['release_date'] as String?,
        previewUrl: json['preview_url'] as String?,
        matchedProvider: json['matched_provider'] as String,
        matchConfidence: (json['match_confidence'] as num?)?.toDouble(),
        platformLinks: (json['platform_links'] as List<dynamic>? ?? [])
            .map((e) => PlatformLink.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'artwork_url': artworkUrl,
        'isrc': isrc,
        'release_date': releaseDate,
        'preview_url': previewUrl,
        'matched_provider': matchedProvider,
        'match_confidence': matchConfidence,
        'platform_links': platformLinks.map((e) => e.toJson()).toList(),
      };
}

/// Os dois modos de captura de áudio que fazem do Salabim um "Shazam + Hum to Search".
enum ListenMode {
  listen('listen', 'Ouvir música'),
  hum('hum', 'Cantar');

  const ListenMode(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

enum TextSearchKind {
  lyrics('lyrics', 'Trecho da letra'),
  description('description', 'Descrever a música');

  const TextSearchKind(this.apiValue, this.label);
  final String apiValue;
  final String label;
}

/// Uma música identificada e salva no histórico local do aparelho — não
/// depende de conta/login (ver HistoryService). `mode` guarda qual provedor
/// bateu essa música ("audd", "acrcloud" ou "musixmatch").
///
/// `wasCorrect` guarda o feedback do usuário sobre esse resultado: null =
/// nunca avaliado, true = confirmou que está certo, false = marcou como
/// errado (nesse caso `correctedTitle`/`correctedArtist` guardam o nome real
/// que o usuário informou, se ele informou).
class HistoryEntry {
  final Track track;
  final String mode;
  final DateTime searchedAt;
  final bool? wasCorrect;
  final String? correctedTitle;
  final String? correctedArtist;

  const HistoryEntry({
    required this.track,
    required this.mode,
    required this.searchedAt,
    this.wasCorrect,
    this.correctedTitle,
    this.correctedArtist,
  });

  /// Título/artista pra exibir na UI — usa a correção do usuário quando ela existir.
  String get displayTitle => correctedTitle ?? track.title;
  String get displayArtist => correctedArtist ?? track.artist;

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        track: Track.fromJson(json['track'] as Map<String, dynamic>),
        mode: json['mode'] as String,
        searchedAt: DateTime.parse(json['searched_at'] as String),
        wasCorrect: json['was_correct'] as bool?,
        correctedTitle: json['corrected_title'] as String?,
        correctedArtist: json['corrected_artist'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'track': track.toJson(),
        'mode': mode,
        'searched_at': searchedAt.toIso8601String(),
        'was_correct': wasCorrect,
        'corrected_title': correctedTitle,
        'corrected_artist': correctedArtist,
      };

  HistoryEntry copyWith({bool? wasCorrect, String? correctedTitle, String? correctedArtist}) {
    return HistoryEntry(
      track: track,
      mode: mode,
      searchedAt: searchedAt,
      wasCorrect: wasCorrect ?? this.wasCorrect,
      correctedTitle: correctedTitle ?? this.correctedTitle,
      correctedArtist: correctedArtist ?? this.correctedArtist,
    );
  }
}
