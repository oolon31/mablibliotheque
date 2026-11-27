import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ma_bibliotheque/models/item.dart';
import 'package:ma_bibliotheque/services/barcode.dart';
import 'package:ma_bibliotheque/services/catalog_lookup.dart';

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name.json').readAsStringSync()) as Map<String, dynamic>;

http.Response jsonResponse(String name) => http.Response.bytes(
  utf8.encode(File('test/fixtures/$name.json').readAsStringSync()),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  videoAndTitleTests();
  group('codes-barres', () {
    test('ISBN-10 converti en ISBN-13', () {
      expect(isbn10To13('220300116X'), '9782203001169');
      expect(isbn10To13('2-07-036002-4'.replaceAll('-', '')), '9782070360024');
      expect(isbn10To13('2203001160'), isNull); // mauvaise clé de contrôle
    });

    test('reconnaît un ISBN et devine le type', () {
      expect(isIsbn('9782070360024'), isTrue);
      expect(isIsbn('978-2-07-036002-4'), isTrue);
      expect(isIsbn('9782070360025'), isFalse); // clé fausse
      expect(guessTypeFromCode('9782070360024'), ItemType.livre);
      expect(guessTypeFromCode('0602537351169'), ItemType.vinyle);
    });

    test('codes plausibles', () {
      expect(isPlausibleCode('0602537351169'), isTrue); // EAN-13
      expect(isPlausibleCode('196587737313'), isTrue); // UPC-A
      expect(isPlausibleCode('12345'), isFalse);
      expect(isPlausibleCode('0602537351168'), isFalse); // clé fausse
    });

    test('un UPC lu avec ou sans zéro initial est le même code', () {
      expect(sameCode('0196587737313', '196587737313'), isTrue);
      expect(sameCode('220300116X', '9782203001169'), isTrue);
      expect(sameCode('9782070360024', '9782203001169'), isFalse);
      expect(sameCode('', '0'), isFalse);
    });
  });

  group('analyse des réponses', () {
    test('accents décomposés recomposés', () {
      expect(composeAccents('On a marche\u0301 sur la lune'), 'On a marché sur la lune');
      expect(composeAccents('Franc\u0327ois, i\u0302le'), 'François, île');
    });

    test('série et tome extraits du titre', () {
      final s = splitSeriesTitle('Les Aventures de Tintin - Tome 17 - On a marché sur la lune')!;
      expect((s.series, s.volume, s.title), ('Les Aventures de Tintin', '17', 'On a marché sur la lune'));
      expect(splitSeriesTitle('Astérix, T.3 : Astérix et les Goths')!.volume, '3');
      expect(splitSeriesTitle('L\'Étranger'), isNull);
    });

    test('Open Library : roman (réponse réelle)', () {
      final r = parseOpenLibrary(fixture('openlibrary_9782070360024'))!;
      expect(r.type, ItemType.livre);
      expect(r.title, 'L’étranger');
      expect(r.creator, 'Albert Camus');
      expect(r.publisher, 'Gallimard');
      expect(r.year, 1972);
    });

    test('Open Library : BD avec série et accents décomposés (réponse réelle)', () {
      final r = parseOpenLibrary(fixture('openlibrary_9782203001169'))!;
      expect(r.type, ItemType.bd);
      expect(r.title, 'On a marché sur la lune');
      expect(r.creator, 'Hergé');
      expect(r.series, 'Les Aventures de Tintin');
      expect(r.year, 1954);
    });

    test('Google Books : BD, lien de couverture en https', () {
      final r = parseGoogleBooks(fixture('googlebooks_9782203001169'))!;
      expect(r.type, ItemType.bd);
      expect((r.series, r.volume, r.title), ('Les Aventures de Tintin', '17', 'On a marché sur la lune'));
      expect(r.coverUrl, startsWith('https://'));
      expect(r.coverUrl, isNot(contains('edge=curl')));
      expect(parseGoogleBooks(fixture('googlebooks_empty')), isNull);
    });

    test('fusion Google Books + Open Library', () {
      final m = mergeBookResults(
        parseGoogleBooks(fixture('googlebooks_9782203001169')),
        parseOpenLibrary(fixture('openlibrary_9782203001169')),
      )!;
      expect(m.type, ItemType.bd);
      expect(m.volume, '17');
      expect(m.year, 1993); // Google en priorité
      expect(m.source, 'Google Books + Open Library');
    });

    test('MusicBrainz : coffret 3 vinyles (réponse réelle)', () {
      final r = parseMusicBrainz(fixture('musicbrainz_196587737313'), '0196587737313')!;
      expect(r.type, ItemType.vinyle);
      expect(r.title, 'Random Access Memories');
      expect(r.creator, 'Daft Punk');
      expect(r.year, 2023);
      expect(r.publisher, 'Rough Trade');
      expect(r.format, 'Coffret');
      expect(r.coverUrl, 'https://coverartarchive.org/release/4375c18f-f160-44d0-ae2b-795f1dd5870f/front-500');
    });

    test('MusicBrainz : ignore les résultats dont le code diffère', () {
      final r = parseMusicBrainz(fixture('musicbrainz_0602537351169'), '0602537351169')!;
      expect(r.creator, 'Johnny Cash');
      expect(parseMusicBrainz(fixture('musicbrainz_0602537351169'), '0000000000000'), isNull);
    });
  });

  group('recherche complète (réseau simulé)', () {
    CatalogLookup lookupWith(http.Response Function(Uri) handler) {
      final l = CatalogLookup(client: MockClient((req) async => handler(req.url)));
      l.retryDelay = Duration.zero;
      return l;
    }

    test('un ISBN interroge les bases de livres', () async {
      final l = lookupWith(
        (u) => switch (u.host) {
          'www.googleapis.com' => jsonResponse('googlebooks_empty'),
          'openlibrary.org' => jsonResponse('openlibrary_9782070360024'),
          _ => http.Response('inattendu', 500),
        },
      );
      final r = await l.lookup('978-2-07-036002-4');
      expect(r!.creator, 'Albert Camus');
      expect(r.source, 'Open Library');
    });

    test('un code EAN de disque interroge MusicBrainz', () async {
      final hosts = <String>[];
      final l = lookupWith((u) {
        hosts.add(u.host);
        return jsonResponse('musicbrainz_196587737313');
      });
      final r = await l.lookup('196587737313');
      expect(r!.type, ItemType.vinyle);
      expect(hosts, ['musicbrainz.org']);
    });

    test('MusicBrainz occupé : une nouvelle tentative réussit', () async {
      var calls = 0;
      final l = lookupWith(
        (u) => ++calls == 1 ? http.Response('{"error":"busy"}', 503) : jsonResponse('musicbrainz_196587737313'),
      );
      expect((await l.lookup('196587737313'))!.title, 'Random Access Memories');
      expect(calls, 2);
    });

    test('MusicBrainz toujours occupé : erreur explicite', () async {
      final l = lookupWith((u) => http.Response('{"error":"busy"}', 503));
      expect(
        () => l.lookup('196587737313'),
        throwsA(isA<LookupException>().having((e) => e.message, 'message', contains('occupé'))),
      );
    });

    test('code inconnu : null, pas d\'erreur', () async {
      final l = lookupWith(
        (u) => switch (u.host) {
          'www.googleapis.com' => jsonResponse('googlebooks_empty'),
          'openlibrary.org' => http.Response('{}', 200),
          'musicbrainz.org' => http.Response('{"releases": []}', 200),
          _ => http.Response('', 404),
        },
      );
      expect(await l.lookup('9782070360024'), isNull);
    });

    test('téléchargement de couverture : refuse les non-images et les pixels vides', () async {
      final big = List<int>.filled(5000, 1);
      final l = lookupWith(
        (u) => switch (u.path) {
          '/ok.jpg' => http.Response.bytes(big, 200, headers: {'content-type': 'image/jpeg'}),
          '/pixel.gif' => http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'image/gif'}),
          '/page.html' => http.Response.bytes(big, 200, headers: {'content-type': 'text/html'}),
          _ => http.Response('', 404),
        },
      );
      expect((await l.downloadImage('https://x.org/ok.jpg'))!.length, 5000);
      expect(await l.downloadImage('https://x.org/pixel.gif'), isNull);
      expect(await l.downloadImage('https://x.org/page.html'), isNull);
      expect(await l.downloadImage('https://x.org/absent.jpg'), isNull);
    });

    test('hors connexion : erreur explicite', () async {
      final l = CatalogLookup(client: MockClient((_) => throw const SocketException('offline')));
      expect(
        () => l.lookup('9782070360024'),
        throwsA(isA<LookupException>().having((e) => e.message, 'message', 'pas de connexion internet')),
      );
      expect(() => l.lookup('196587737313'), throwsA(isA<LookupException>()));
    });
  });
}

// Films et recherche par titre.
void videoAndTitleTests() {
  group('films (UPCitemdb) et recherche par titre', () {
    test('un Blu-ray est reconnu, son titre est nettoyé des mentions de format', () {
      final json = {
        'code': 'OK',
        'items': [
          {
            'title': 'Dune [Blu-ray] + DVD',
            'brand': 'Warner Bros',
            'category': 'Movies & TV',
            'images': ['https://images.example.com/dune.jpg'],
          },
        ],
      };
      final r = parseUpcItemDb(json, '0883929000000')!;
      expect(r.type, ItemType.bluray);
      expect(r.title, 'Dune');
      expect(r.publisher, 'Warner Bros');
      expect(r.coverUrl, 'https://images.example.com/dune.jpg');
    });

    test('un DVD simple est un DVD ; un produit musical est laissé à MusicBrainz', () {
      expect(
        parseUpcItemDb({
          'items': [
            {'title': 'Amélie - DVD'},
          ],
        }, '1')!.type,
        ItemType.dvd,
      );
      expect(cleanVideoTitle('Amélie - DVD'), 'Amélie');
      expect(
        parseUpcItemDb({
          'items': [
            {'title': 'Random Access Memories', 'category': 'Music'},
          ],
        }, '1'),
        isNull,
      );
      expect(parseUpcItemDb({'items': []}, '1'), isNull);
    });

    test('recherche par titre : résultats Open Library réels, ISBN-13 retenu', () {
      final matches = parseOpenLibrarySearch(fixture('openlibrary_search_lune'));
      expect(matches, isNotEmpty);
      final tintin = matches.firstWhere((m) => m.isbn == '9782203001169', orElse: () => matches.first);
      expect(tintin.title.toLowerCase(), contains('lune'));
      expect(tintin.creator, contains('Hergé'));
      expect(matches.every((m) => m.isbn == null || isIsbn(m.isbn!)), isTrue);
    });

    test('un set LEGO est reconnu avec son nombre de pièces, sans le mot LEGO dans le titre', () {
      final r = parseUpcItemDb({
        'items': [
          {
            'title': 'LEGO® Star Wars Faucon Millenium 75257 - 1351 pièces',
            'brand': 'LEGO',
            'category': 'Toys & Games',
          },
        ],
      }, '5702016370034')!;
      expect(r.type, ItemType.lego);
      expect(r.title, 'Star Wars Faucon Millenium 75257 - 1351 pièces');
      expect(r.volume, '1351');
      expect(r.publisher, 'LEGO');
    });

    test('les codes-barres LEGO sont reconnus par leur préfixe', () {
      expect(guessTypeFromCode('5702016370034'), ItemType.lego);
      expect(guessTypeFromCode('5702017153469'), ItemType.lego);
      expect(guessTypeFromCode('0673419340144'), ItemType.lego);
      expect(guessTypeFromCode('9782070360024'), ItemType.livre);
      expect(guessTypeFromCode('196587737313'), ItemType.vinyle);
    });

    test('un résultat de recherche devient une fiche livre prête à enregistrer', () {
      const m = TitleMatch(title: 'On a marché sur la lune', creator: 'Hergé', year: 1954, isbn: '9782203001169');
      final r = m.toLookup();
      expect(r.type, ItemType.livre);
      expect(r.creator, 'Hergé');
      expect(r.year, 1954);
    });
  });
}
