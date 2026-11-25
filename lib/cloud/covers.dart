import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Les couvertures sont stockées dans le bucket privé « covers ».
///   - Chemin distant (ex. `<owner>/123_456.jpg`) : déjà envoyé au serveur.
///   - Chemin local absolu (commence par « / ») : image choisie, pas encore envoyée.
const _bucket = 'covers';

bool isLocalCover(String? path) => path != null && path.startsWith('/');

String _randomName() {
  final r = Random.secure();
  return List.generate(8, (_) => r.nextInt(16).toRadixString(16)).join();
}

String _contentType(String ext) => switch (ext.toLowerCase()) {
  '.png' => 'image/png',
  '.webp' => 'image/webp',
  '.gif' => 'image/gif',
  _ => 'image/jpeg',
};

class CloudCovers {
  CloudCovers._();

  static SupabaseStorageClient get _storage => Supabase.instance.client.storage;

  static final Map<String, Future<String?>> _urls = {};

  /// URL temporaire (1 h) pour afficher une couverture distante. Null si introuvable.
  static Future<String?> url(String path) {
    return _urls.putIfAbsent(path, () async {
      try {
        return await _storage.from(_bucket).createSignedUrl(path, 3600);
      } catch (_) {
        _urls.remove(path); // on réessaiera à l'affichage suivant
        return null;
      }
    });
  }

  /// Envoie une image locale et renvoie son chemin distant. Le fichier local n'est pas supprimé ici.
  static Future<String> upload(String ownerId, String localPath) async {
    final ext = p.extension(localPath).isEmpty ? '.jpg' : p.extension(localPath);
    final remote = '$ownerId/${DateTime.now().millisecondsSinceEpoch}_${_randomName()}$ext';
    await _storage
        .from(_bucket)
        .uploadBinary(
          remote,
          await File(localPath).readAsBytes(),
          fileOptions: FileOptions(contentType: _contentType(ext), upsert: false),
        );
    return remote;
  }

  /// Envoie des octets bruts (restauration) et renvoie le chemin distant.
  static Future<String> uploadBytes(String ownerId, List<int> bytes, String ext) async {
    final remote = '$ownerId/${DateTime.now().millisecondsSinceEpoch}_${_randomName()}$ext';
    await _storage
        .from(_bucket)
        .uploadBinary(
          remote,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(contentType: _contentType(ext), upsert: false),
        );
    return remote;
  }

  /// Octets d'une couverture, qu'elle soit locale ou distante. Null si indisponible.
  static Future<List<int>?> read(String? path) async {
    if (path == null) return null;
    try {
      if (isLocalCover(path)) {
        final f = File(path);
        return await f.exists() ? await f.readAsBytes() : null;
      }
      return await _storage.from(_bucket).download(path);
    } catch (_) {
      return null;
    }
  }

  /// Supprime des couvertures distantes. Les erreurs sont ignorées : c'est un nettoyage.
  static Future<void> remove(Iterable<String?> paths) async {
    final remote = paths.where((p) => p != null && !isLocalCover(p)).cast<String>().toList();
    if (remote.isEmpty) return;
    try {
      await _storage.from(_bucket).remove(remote);
    } catch (_) {}
    for (final r in remote) {
      _urls.remove(r);
    }
  }
}
