import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/item.dart';
import 'barcode.dart';

/// Fiche trouvée en ligne à partir d'un code-barres.
class LookupResult {
  const LookupResult({
    required this.type,
    required this.title,
    this.creator = '',
    this.year,
    this.publisher = '',
    this.series = '',
    this.volume = '',
    this.genre = '',
    this.format = '',
    this.coverUrl,
    required this.source,
  });

  final ItemType type;
  final String title;
  final String creator;
  final int? year;
  final String publisher;
  final String series;
  final String volume;
  final String genre;
  final String format;
  final String? coverUrl;

  /// Base qui a fourni la fiche (affichée à l'utilisateur).
  final String source;

  LookupResult copyWith({
    ItemType? type,
    String? series,
    String? volume,
    String? title,
    String? coverUrl,
    String? genre,
  }) => LookupResult(
    type: type ?? this.type,
    title: title ?? this.title,
    creator: creator,
    year: year,
    publisher: publisher,
    series: series ?? this.series,
    volume: volume ?? this.volume,
    genre: genre ?? this.genre,
    format: format,
    coverUrl: coverUrl ?? this.coverUrl,
    source: source,
  );
}

/// Erreur réseau : la recherche n'a pas pu aboutir (différent de « rien trouvé »).
class LookupException implements Exception {
  const LookupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Recherche une fiche dans des bases publiques gratuites, sans clé d'API :
/// Google Books et Open Library pour les livres et BD, MusicBrainz pour les disques.
class CatalogLookup {
  CatalogLookup({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _headers = {
    'User-Agent': 'MaBibliotheque/1.0 (application personnelle Android)',
    'Accept': 'application/json',
  };
  static const _timeout = Duration(seconds: 12);

  /// Renvoie null si aucune base ne connaît ce code.
  Future<LookupResult?> lookup(String rawCode) async {
    final code = normalizeCode(rawCode);
    if (isIsbn(code)) {
      // Un ISBN inconnu des bases de livres a peu de chances d'être un disque :
      // une erreur de MusicBrainz ne doit pas masquer le simple « rien trouvé ».
      return await _book(code) ?? await _music(code).catchError((Object _) => null);
    }
    return await _music(code) ?? await _book(code);
  }

  Future<LookupResult?> _book(String isbn) async {
    // Les deux bases sont interrogées en parallèle puis combinées.
    final results = await Future.wait([
      _getJson('https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn')
          .then((j) => j == null ? null : parseGoogleBooks(j), onError: (Object _) => null),
      _getJson('https://openlibrary.org/api/books?bibkeys=ISBN:$isbn&format=json&jscmd=data')
          .then((j) => j == null ? null : parseOpenLibrary(j), onError: (Object _) => null),
    ]);
    final merged = mergeBookResults(results[0], results[1]);
    if (merged != null) return merged;
    // Aucune fiche : était-ce faute de réseau ?
    await _checkConnectivity();
    return null;
  }

  Future<LookupResult?> _music(String code) async {
    // Un UPC-A (12 chiffres) peut être lu comme EAN-13 avec un zéro devant.
    final variants = {code, code.replaceFirst(RegExp(r'^0+'), ''), if (code.length == 12) '0$code'};
    final query = variants.map((v) => 'barcode:$v').join(' OR ');
    final json = await _getJson(
      'https://musicbrainz.org/ws/2/release/?query=${Uri.encodeQueryComponent(query)}&fmt=json&limit=15',
    );
    return json == null ? null : parseMusicBrainz(json, code);
  }

  Future<void> _checkConnectivity() async {
    try {
      await _client.head(Uri.parse('https://musicbrainz.org/'), headers: _headers).timeout(_timeout);
    } catch (_) {
      throw const LookupException('pas de connexion internet');
    }
  }

  /// Délai avant une nouvelle tentative quand un serveur est surchargé (modifiable pour les tests).
  Duration retryDelay = const Duration(milliseconds: 1500);

  Future<Map<String, dynamic>?> _getJson(String url, {bool retry = true}) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse(url), headers: _headers).timeout(_timeout);
    } on TimeoutException {
      throw const LookupException('le serveur ne répond pas');
    } catch (_) {
      throw const LookupException('pas de connexion internet');
    }
    // MusicBrainz répond 503 au-delà d'une requête par seconde : on réessaie une fois.
    if (res.statusCode == 503 || res.statusCode == 429) {
      if (retry) {
        await Future<void>.delayed(retryDelay);
        return _getJson(url, retry: false);
      }
      throw const LookupException('serveur occupé, réessayez dans un instant');
    }
    if (res.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is Map<String, dynamic> ? body : null;
  }

  /// Télécharge une image ; renvoie ses octets, ou null si indisponible.
  Future<List<int>?> downloadImage(String url) async {
    try {
      final res = await _client.get(Uri.parse(url), headers: {'User-Agent': _headers['User-Agent']!}).timeout(_timeout);
      final type = res.headers['content-type'] ?? '';
      // Une image de moins de 1 Ko est un pixel de remplacement, pas une vraie couverture.
      if (res.statusCode == 200 && type.startsWith('image/') && res.bodyBytes.length > 1000) {
        return res.bodyBytes;
      }
    } catch (_) {}
    return null;
  }
}

// ---------------------------------------------------------------------------
// Analyse des réponses (fonctions pures, testées avec de vraies réponses).

/// Recompose les accents décomposés (« e » + accent combinant → « é »),
/// fréquents dans les titres d'Open Library.
String composeAccents(String s) {
  const marks = {
    '́': {'a': 'á', 'e': 'é', 'i': 'í', 'o': 'ó', 'u': 'ú', 'y': 'ý', 'A': 'Á', 'E': 'É', 'I': 'Í', 'O': 'Ó', 'U': 'Ú'},
    '̀': {'a': 'à', 'e': 'è', 'i': 'ì', 'o': 'ò', 'u': 'ù', 'A': 'À', 'E': 'È', 'U': 'Ù'},
    '̂': {'a': 'â', 'e': 'ê', 'i': 'î', 'o': 'ô', 'u': 'û', 'A': 'Â', 'E': 'Ê', 'I': 'Î', 'O': 'Ô', 'U': 'Û'},
    '̈': {'a': 'ä', 'e': 'ë', 'i': 'ï', 'o': 'ö', 'u': 'ü', 'y': 'ÿ', 'A': 'Ä', 'E': 'Ë', 'I': 'Ï', 'O': 'Ö', 'U': 'Ü'},
    '̧': {'c': 'ç', 'C': 'Ç'},
    '̃': {'a': 'ã', 'n': 'ñ', 'o': 'õ', 'N': 'Ñ'},
  };
  final out = StringBuffer();
  final chars = s.split('');
  for (var i = 0; i < chars.length; i++) {
    final next = i + 1 < chars.length ? chars[i + 1] : '';
    final composed = marks[next]?[chars[i]];
    if (composed != null) {
      out.write(composed);
      i++;
    } else {
      out.write(chars[i]);
    }
  }
  return out.toString();
}

int? _year(Object? date) {
  final m = RegExp(r'\b(1[5-9]\d\d|20\d\d)\b').firstMatch('${date ?? ''}');
  return m == null ? null : int.parse(m.group(1)!);
}

String _str(Object? v) => v is String ? composeAccents(v.trim()) : '';

/// Éditeurs dont le catalogue est essentiellement composé de BD et de mangas.
const _bdPublishers = [
  'casterman',
  'dargaud',
  'dupuis',
  'lombard',
  'glénat',
  'glenat',
  'delcourt',
  'soleil',
  'futuropolis',
  'bamboo',
  'humanoïdes',
  'humanoides',
  'kana',
  'pika',
  'ki-oon',
  'kurokawa',
  'urban comics',
  'panini comics',
  'fluide glacial',
  'rue de sèvres',
  'marsu',
  'grand angle',
  'vents d\'ouest',
  'dupuis jeunesse',
];

bool _hasComicSubject(Iterable<String> subjects) => subjects
    .map((s) => s.toLowerCase())
    .any(
      (s) =>
          s.contains('comic') ||
          s.contains('graphic novel') ||
          s.contains('bandes dessinées') ||
          s.contains('bande dessinée') ||
          s.contains('manga'),
    );

bool _isBdPublisher(String publisher) {
  final p = publisher.toLowerCase();
  return _bdPublishers.any(p.contains);
}

/// Catégories Google Books (en anglais) → genre en français. Les autres sont ignorées.
const _genres = {
  'fiction': 'Roman',
  'science fiction': 'Science-fiction',
  'fantasy': 'Fantasy',
  'history': 'Histoire',
  'biography & autobiography': 'Biographie',
  'juvenile fiction': 'Jeunesse',
  'juvenile nonfiction': 'Jeunesse',
  'young adult fiction': 'Jeunesse',
  'cooking': 'Cuisine',
  'poetry': 'Poésie',
  'philosophy': 'Philosophie',
  'drama': 'Théâtre',
  'travel': 'Voyage',
  'art': 'Art',
  'music': 'Musique',
  'humor': 'Humour',
  'true crime': 'Policier',
  'detective and mystery stories': 'Policier',
  'mystery': 'Policier',
  'science': 'Sciences',
  'psychology': 'Psychologie',
  'religion': 'Religion',
  'political science': 'Politique',
  'social science': 'Sciences sociales',
  'self-help': 'Développement personnel',
};

String _genreFrom(Iterable<String> categories) {
  for (final c in categories) {
    final key = c.toLowerCase().split('/').first.trim();
    final g = _genres[key];
    if (g != null) return g;
  }
  return '';
}

/// « Les Aventures de Tintin - Tome 17 - On a marché sur la lune » → série, tome, titre.
({String series, String volume, String title})? splitSeriesTitle(String title) {
  final m = RegExp(
    r'^(.+?)\s*[-–—:,.]\s*(?:tome|t\.|vol\.?|volume|n°)\s*(\d+)\s*(?:[-–—:,.]\s*(.*))?$',
    caseSensitive: false,
  ).firstMatch(title.trim());
  if (m == null) return null;
  final rest = (m.group(3) ?? '').trim();
  return (series: m.group(1)!.trim(), volume: m.group(2)!, title: rest.isEmpty ? title.trim() : rest);
}

LookupResult? parseGoogleBooks(Map<String, dynamic> json) {
  final items = json['items'];
  if (items is! List || items.isEmpty) return null;
  final info = (items.first as Map)['volumeInfo'] as Map? ?? const {};
  final title = _str(info['title']);
  if (title.isEmpty) return null;
  final authors = (info['authors'] as List?)?.whereType<String>().map(composeAccents).join(', ') ?? '';
  final categories = (info['categories'] as List?)?.whereType<String>().toList() ?? const <String>[];
  final publisher = _str(info['publisher']);
  final images = info['imageLinks'] as Map? ?? const {};
  String? cover = (images['thumbnail'] ?? images['smallThumbnail']) as String?;
  // Google renvoie des liens http, et « edge=curl » ajoute un effet de page cornée.
  cover = cover?.replaceFirst('http://', 'https://').replaceAll('&edge=curl', '');
  // Les catégories Google Books décrivent cette édition précise : on peut s'y fier.
  final isBd = _hasComicSubject(categories) || _isBdPublisher(publisher);
  var result = LookupResult(
    type: isBd ? ItemType.bd : ItemType.livre,
    title: title,
    creator: authors,
    year: _year(info['publishedDate']),
    publisher: publisher,
    genre: isBd ? '' : _genreFrom(categories),
    coverUrl: cover,
    source: 'Google Books',
  );
  final split = splitSeriesTitle(title);
  if (split != null) result = result.copyWith(series: split.series, volume: split.volume, title: split.title);
  return result;
}

LookupResult? parseOpenLibrary(Map<String, dynamic> json) {
  if (json.isEmpty) return null;
  final book = json.values.first;
  if (book is! Map) return null;
  final title = _str(book['title']);
  if (title.isEmpty) return null;
  final authors = (book['authors'] as List? ?? const [])
      .whereType<Map>()
      .map((a) => _str(a['name']))
      .where((n) => n.isNotEmpty)
      .join(', ');
  final publishers = (book['publishers'] as List? ?? const []).whereType<Map>().map((p) => _str(p['name']));
  final publisher = publishers.isEmpty ? '' : publishers.first;
  final subjects = (book['subjects'] as List? ?? const []).whereType<Map>().map((s) => _str(s['name'])).toList();
  // Open Library indique souvent la série dans un sujet « series:… ».
  var series = '';
  for (final s in subjects) {
    if (s.toLowerCase().startsWith('series:')) {
      series = s.substring(7).replaceAll('_', ' ').trim();
      break;
    }
  }
  final cover = book['cover'] as Map?;
  // Les sujets d'Open Library mélangent toutes les éditions d'une œuvre (L'Étranger de Camus
  // a « Comics & graphic novels » à cause d'une adaptation) : un sujet BD ne suffit que pour
  // un ouvrage court.
  final pages = book['number_of_pages'];
  final isBd = _isBdPublisher(publisher) || (_hasComicSubject(subjects) && pages is int && pages > 0 && pages <= 120);
  var result = LookupResult(
    type: isBd ? ItemType.bd : ItemType.livre,
    title: title,
    creator: authors,
    year: _year(book['publish_date']),
    publisher: publisher,
    series: series,
    coverUrl: (cover?['large'] ?? cover?['medium']) as String?,
    source: 'Open Library',
  );
  final split = splitSeriesTitle(title);
  if (split != null) {
    result = result.copyWith(series: series.isEmpty ? split.series : series, volume: split.volume, title: split.title);
  }
  return result;
}

/// Combine les deux sources : Google Books en priorité, Open Library pour compléter.
LookupResult? mergeBookResults(LookupResult? google, LookupResult? openLibrary) {
  if (google == null) return openLibrary;
  if (openLibrary == null) return google;
  String pick(String a, String b) => a.isNotEmpty ? a : b;
  final isBd = google.type == ItemType.bd || openLibrary.type == ItemType.bd;
  return LookupResult(
    type: isBd ? ItemType.bd : ItemType.livre,
    title: google.title,
    creator: pick(google.creator, openLibrary.creator),
    year: google.year ?? openLibrary.year,
    publisher: pick(google.publisher, openLibrary.publisher),
    series: pick(google.series, openLibrary.series),
    volume: pick(google.volume, openLibrary.volume),
    genre: isBd ? '' : pick(google.genre, openLibrary.genre),
    coverUrl: openLibrary.coverUrl ?? google.coverUrl,
    source: 'Google Books + Open Library',
  );
}

LookupResult? parseMusicBrainz(Map<String, dynamic> json, String code) {
  final releases = (json['releases'] as List? ?? const [])
      .whereType<Map>()
      // La recherche est approximative : on ne garde que les codes identiques.
      .where((r) => r['barcode'] is String && sameCode(r['barcode'] as String, code))
      .toList();
  if (releases.isEmpty) return null;

  List<String> formats(Map r) =>
      (r['media'] as List? ?? const []).whereType<Map>().map((m) => '${m['format'] ?? ''}').toList();
  final release = releases.firstWhere((r) => formats(r).any((f) => f.contains('Vinyl')), orElse: () => releases.first);

  final credits = (release['artist-credit'] as List? ?? const []).whereType<Map>();
  final artist = credits.map((c) => '${_str(c['name'])}${c['joinphrase'] ?? ''}').join().trim();
  final labels = (release['label-info'] as List? ?? const [])
      .whereType<Map>()
      .map((l) => _str((l['label'] as Map?)?['name']))
      .where((n) => n.isNotEmpty);
  final media = formats(release);
  var format = '';
  if (media.any((f) => f.contains('7"'))) {
    format = '45 tours';
  } else if (media.where((f) => f.contains('Vinyl')).length >= 3) {
    format = 'Coffret';
  } else if (media.where((f) => f.contains('Vinyl')).length == 2) {
    format = 'Double album';
  } else if (media.any((f) => f.contains('Vinyl'))) {
    format = '33 tours (LP)';
  }
  final id = release['id'] as String?;
  return LookupResult(
    type: ItemType.vinyle,
    title: _str(release['title']),
    creator: artist,
    year: _year(release['date']),
    publisher: labels.isEmpty ? '' : labels.first,
    format: format,
    coverUrl: id == null ? null : 'https://coverartarchive.org/release/$id/front-500',
    source: 'MusicBrainz',
  );
}
