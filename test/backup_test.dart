import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ma_bibliotheque/data/demo_data.dart';
import 'package:ma_bibliotheque/data/item_repository.dart';
import 'package:ma_bibliotheque/data/sqlite_item_repository.dart';
import 'package:ma_bibliotheque/models/item.dart';
import 'package:ma_bibliotheque/services/backup.dart';
import 'package:ma_bibliotheque/state/library.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> comparable(Item i) => i.toMap()
  ..remove('id')
  ..remove('cover_path');

List<int> zipWith(String manifest) {
  final a = Archive()..addFile(ArchiveFile.string('bibliotheque.json', manifest));
  return ZipEncoder().encodeBytes(a);
}

void main() {
  final items = demoItems();
  final png = List<int>.generate(3000, (i) => i % 256);

  group('format de sauvegarde', () {
    test('aller-retour complet : tous les champs, couvertures et date', () {
      final entries = [
        BackupEntry(items[0], cover: png, coverExtension: '.png'),
        for (final i in items.skip(1)) BackupEntry(i),
      ];
      final when = DateTime(2026, 11, 24, 18, 30);
      final back = decodeBackup(encodeBackup(entries, now: when));

      expect(back.createdAt, when);
      expect(back.entries.length, items.length);
      for (var k = 0; k < items.length; k++) {
        expect(comparable(back.entries[k].item), comparable(items[k]), reason: items[k].title);
      }
      expect(back.entries[0].cover, png);
      expect(back.entries[0].coverExtension, '.png');
      expect(back.entries[1].cover, isNull);
      // Le prêt et la liste d'envies sont conservés.
      expect(back.entries.where((e) => e.item.isLoaned).length, 2);
      expect(back.wishlistCount, 2);
      expect(back.count(ItemType.bd), 3);
    });

    test('le fichier contient une liste JSON lisible', () {
      final zip = ZipDecoder().decodeBytes(encodeBackup([BackupEntry(items[3])]));
      final json = jsonDecode(utf8.decode(zip.findFile('bibliotheque.json')!.content)) as Map;
      expect(json['format'], 'ma-bibliotheque');
      expect(json['count'], 1);
      expect((json['items'] as List).single['title'], 'L\'Étranger');
      expect((json['items'] as List).single.containsKey('id'), isFalse);
    });

    test('nom de fichier daté', () {
      expect(backupFileName(DateTime(2026, 3, 7)), 'ma-bibliotheque-2026-03-07.zip');
    });

    test('un fichier quelconque est refusé', () {
      expect(
        () => decodeBackup(utf8.encode('bonjour')),
        throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('n\'est pas une sauvegarde'))),
      );
      final otherZip = ZipEncoder().encodeBytes(Archive()..addFile(ArchiveFile.string('autre.txt', 'x')));
      expect(() => decodeBackup(otherZip), throwsA(isA<BackupException>()));
      expect(
        () => decodeBackup(zipWith('{"format": "autre", "version": 1, "items": []}')),
        throwsA(isA<BackupException>()),
      );
    });

    test('une sauvegarde d\'une version future est refusée avec un message clair', () {
      expect(
        () => decodeBackup(zipWith('{"format": "ma-bibliotheque", "version": 99, "items": []}')),
        throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('plus récente'))),
      );
    });

    test('un objet endommagé est signalé avec son numéro', () {
      final ok = jsonEncode(comparable(items[0]));
      expect(
        () => decodeBackup(zipWith('{"format": "ma-bibliotheque", "version": 1, "items": [$ok, {"title": 3}]}')),
        throwsA(isA<BackupException>().having((e) => e.message, 'm', contains('n° 2'))),
      );
    });

    test('une couverture manquante n\'empêche pas la restauration', () {
      final map = comparable(items[0])..['cover'] = 'covers/1.jpg';
      final back = decodeBackup(
        zipWith(
          jsonEncode({
            'format': 'ma-bibliotheque',
            'version': 1,
            'items': [map],
          }),
        ),
      );
      expect(back.entries.single.item.title, items[0].title);
      expect(back.entries.single.cover, isNull);
    });
  });

  group('fusion', () {
    test('même code-barres = même objet, même si le titre diffère', () {
      final a = Item(type: ItemType.livre, title: 'Dune', identifier: '9782221252055', createdAt: DateTime(2020));
      final b = a.copyWith(title: 'Dune (édition poche)');
      expect(isSameItem(a, b), isTrue);
      expect(isSameItem(a, b.copyWith(identifier: '9782266320481')), isFalse);
    });

    test('sans code : titre, auteur et tome, sans tenir compte des accents', () {
      final a = Item(
        type: ItemType.bd,
        title: 'Astérix le Gaulois',
        creator: 'Goscinny',
        series: 'Astérix',
        volume: '1',
        createdAt: DateTime(2020),
      );
      expect(isSameItem(a, a.copyWith(title: 'ASTERIX LE GAULOIS ')), isTrue);
      expect(isSameItem(a, a.copyWith(volume: '2')), isFalse);
      expect(isSameItem(a, a.copyWith(type: ItemType.livre)), isFalse);
    });

    test('n\'ajoute que les nouveautés, garde les exemplaires multiples de la sauvegarde', () {
      final existing = items.take(4).toList();
      final incoming = [
        for (final i in items) BackupEntry(i),
        BackupEntry(items.last), // deuxième exemplaire voulu
      ];
      final added = newEntries(existing, incoming);
      expect(added.length, items.length - 4 + 1);
      expect(added.map((e) => e.item.title), isNot(contains(items[0].title)));
    });
  });

  group('restauration dans la bibliothèque', () {
    test('remplacer puis fusionner (mémoire)', () async {
      final library = Library(MemoryItemRepository(items.take(2).toList()));
      await library.load();

      final restored = await library.restore(items.skip(5).toList(), replace: true);
      expect(library.items.length, items.length - 5);
      expect(restored.every((i) => i.id != null), isTrue);
      expect(library.items.map((i) => i.title), isNot(contains(items[0].title)));

      await library.restore([items[0]], replace: false);
      expect(library.items.length, items.length - 4);
    });

    test('avec la vraie base SQLite', () async {
      sqfliteFfiInit();
      final repo = await SqliteItemRepository.open(path: inMemoryDatabasePath, factory: databaseFactoryFfi);
      await repo.insertAll(items.take(3).toList());

      // Sauvegarde → fichier → restauration en remplacement.
      final file = encodeBackup([for (final i in await repo.all()) BackupEntry(i.copyWith(id: null))]);
      await repo.insertAll(items.skip(3).toList());
      expect((await repo.all()).length, items.length);

      final contents = decodeBackup(file);
      await repo.insertAll([for (final e in contents.entries) e.item], replace: true);
      final after = await repo.all();
      expect(after.length, 3);
      expect(after.map(comparable).toList(), items.take(3).map(comparable).toList());
    });
  });
}
