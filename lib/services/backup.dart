import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models/item.dart';
import '../state/library.dart' show normalize;
import 'barcode.dart';

/// Une sauvegarde est un fichier .zip contenant :
///   bibliotheque.json  la liste des objets (lisible par n'importe quel outil)
///   covers/…           les images de couverture
const backupFormat = 'ma-bibliotheque';
const backupVersion = 1;
const _manifestName = 'bibliotheque.json';

class BackupEntry {
  const BackupEntry(this.item, {this.cover, this.coverExtension = '.jpg'});

  /// L'objet, sans identifiant ni chemin de couverture (propres à chaque téléphone).
  final Item item;
  final List<int>? cover;
  final String coverExtension;
}

class BackupContents {
  const BackupContents({required this.entries, required this.createdAt});
  final List<BackupEntry> entries;
  final DateTime createdAt;

  int count(ItemType type) => entries.where((e) => e.item.type == type && !e.item.wishlist).length;
  int get wishlistCount => entries.where((e) => e.item.wishlist).length;
}

class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

String backupFileName(DateTime d) =>
    'ma-bibliotheque-${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}.zip';

/// Fabrique le fichier de sauvegarde. Fonction pure, exécutable hors du fil principal.
Uint8List encodeBackup(List<BackupEntry> entries, {DateTime? now}) {
  final archive = Archive();
  final items = <Map<String, Object?>>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    final map = e.item.toMap()
      ..remove('id')
      ..remove('cover_path');
    if (e.cover != null && e.cover!.isNotEmpty) {
      final name = 'covers/${i + 1}${e.coverExtension}';
      // Les images sont déjà compressées : inutile de les recompresser.
      archive.addFile(ArchiveFile.noCompress(name, e.cover!.length, e.cover!));
      map['cover'] = name;
    }
    items.add(map);
  }
  final manifest = {
    'format': backupFormat,
    'version': backupVersion,
    'created_at': (now ?? DateTime.now()).toIso8601String(),
    'count': items.length,
    'items': items,
  };
  archive.addFile(ArchiveFile.string(_manifestName, const JsonEncoder.withIndent(' ').convert(manifest)));
  return ZipEncoder().encodeBytes(archive);
}

/// Lit un fichier de sauvegarde, en vérifiant qu'il est complet et compatible.
BackupContents decodeBackup(List<int> bytes) {
  const notABackup = BackupException('Ce fichier n\'est pas une sauvegarde de Ma Bibliothèque.');
  final Archive archive;
  try {
    archive = ZipDecoder().decodeBytes(bytes);
  } catch (_) {
    throw notABackup;
  }
  final manifestFile = archive.findFile(_manifestName);
  if (manifestFile == null) throw notABackup;

  final Object? manifest;
  try {
    manifest = jsonDecode(utf8.decode(manifestFile.content));
  } catch (_) {
    throw const BackupException('La sauvegarde est endommagée (liste illisible).');
  }
  if (manifest is! Map || manifest['format'] != backupFormat || manifest['items'] is! List) throw notABackup;
  final version = manifest['version'];
  if (version is! int || version > backupVersion) {
    throw const BackupException(
      'Cette sauvegarde vient d\'une version plus récente de l\'application. Mettez d\'abord l\'application à jour.',
    );
  }

  final entries = <BackupEntry>[];
  final list = manifest['items'] as List;
  for (var i = 0; i < list.length; i++) {
    final raw = list[i];
    try {
      final map = Map<String, Object?>.from(raw as Map)
        ..remove('id')
        ..remove('cover_path');
      final coverName = map.remove('cover') as String?;
      final item = Item.fromMap(map);
      List<int>? cover;
      var ext = '.jpg';
      if (coverName != null) {
        // Une couverture manquante n'empêche pas de restaurer l'objet.
        final f = archive.findFile(coverName);
        if (f != null && f.content.isNotEmpty) cover = f.content;
        final dot = coverName.lastIndexOf('.');
        if (dot > coverName.lastIndexOf('/')) ext = coverName.substring(dot);
      }
      entries.add(BackupEntry(item, cover: cover, coverExtension: ext));
    } catch (_) {
      throw BackupException('La sauvegarde est endommagée (objet n° ${i + 1} illisible).');
    }
  }
  final created = DateTime.tryParse('${manifest['created_at']}') ?? DateTime.now();
  return BackupContents(entries: entries, createdAt: created);
}

/// Deux fiches désignent-elles le même objet ? Même code-barres, ou à défaut
/// même type, même titre, même auteur et même tome.
bool isSameItem(Item a, Item b) {
  if (a.identifier.isNotEmpty && b.identifier.isNotEmpty) return sameCode(a.identifier, b.identifier);
  return a.type == b.type &&
      normalize(a.title.trim()) == normalize(b.title.trim()) &&
      normalize(a.creator.trim()) == normalize(b.creator.trim()) &&
      normalize(a.series.trim()) == normalize(b.series.trim()) &&
      a.volume.trim() == b.volume.trim();
}

/// Pour une fusion : les objets de la sauvegarde absents de la bibliothèque actuelle.
/// Les exemplaires multiples présents dans la sauvegarde elle-même sont conservés.
List<BackupEntry> newEntries(Iterable<Item> existing, List<BackupEntry> incoming) {
  final current = existing.toList();
  return incoming.where((e) => !current.any((i) => isSameItem(i, e.item))).toList();
}
