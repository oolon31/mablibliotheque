import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../cloud/covers.dart';
import '../models/item.dart';

/// Couleur associée à chaque type, dérivée du thème.
Color typeColor(BuildContext context, ItemType type) {
  final scheme = Theme.of(context).colorScheme;
  return switch (type) {
    ItemType.vinyle => scheme.primary,
    ItemType.livre => scheme.tertiary,
    ItemType.dvd => const Color(0xFF7B5EA7),
    ItemType.bluray => const Color(0xFF1F7F8A),
    ItemType.bd => _bdColors.putIfAbsent(
      scheme.brightness,
      () => ColorScheme.fromSeed(seedColor: const Color(0xFF2F6A8C), brightness: scheme.brightness).primary,
    ),
  };
}

final Map<Brightness, Color> _bdColors = {};

/// Pochette ou couverture ; à défaut, l'icône du type sur fond coloré.
class Cover extends StatelessWidget {
  const Cover({super.key, required this.item, this.width = 48, this.radius = 8});

  final Item item;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    // Pochette de vinyle carrée, livre et BD au format portrait.
    final height = item.type == ItemType.vinyle ? width : width * 1.4;
    final path = item.coverPath;
    final color = typeColor(context, item.type);
    Widget placeholder() => Container(
      width: width,
      height: height,
      color: color.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Icon(item.type.icon, color: color, size: width * 0.5),
    );

    Widget child;
    if (path == null) {
      child = placeholder();
    } else if (isLocalCover(path)) {
      // Image choisie sur ce téléphone, pas encore envoyée.
      child = File(path).existsSync()
          ? Image.file(File(path), fit: BoxFit.cover, width: width, height: height)
          : placeholder();
    } else {
      // Image hébergée : URL temporaire obtenue auprès du serveur.
      child = FutureBuilder<String?>(
        future: CloudCovers.url(path),
        builder: (context, snap) {
          final url = snap.data;
          if (url == null) return placeholder();
          return Image.network(
            url,
            fit: BoxFit.cover,
            width: width,
            height: height,
            errorBuilder: (context, error, stackTrace) => placeholder(),
          );
        },
      );
    }
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: child);
  }
}

/// Copie une image choisie (appareil photo ou galerie) dans le dossier de l'application.
Future<String?> pickCover(ImageSource source) async {
  final picked = await ImagePicker().pickImage(source: source, maxWidth: 1200, imageQuality: 85);
  if (picked == null) return null;
  return saveCoverBytes(await File(picked.path).readAsBytes(), p.extension(picked.path));
}

int _coverSeq = 0;

/// Enregistre une image dans le dossier des couvertures et renvoie son chemin.
Future<String> saveCoverBytes(List<int> bytes, [String extension = '.jpg']) async {
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'covers'));
  await dir.create(recursive: true);
  final dest = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}_${_coverSeq++}$extension');
  await File(dest).writeAsBytes(bytes);
  return dest;
}

Future<void> deleteCoverFile(String? path) async {
  if (kIsWeb || path == null) return;
  final f = File(path);
  if (await f.exists()) await f.delete();
}
