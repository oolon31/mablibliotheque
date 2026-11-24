import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;

import '../models/item.dart';
import '../services/backup.dart';
import '../state/library.dart';
import '../widgets/cover.dart';

/// Affiche une fenêtre d'attente pendant [task].
Future<T> _withProgress<T>(BuildContext context, String message, Future<T> Function() task) async {
  final nav = Navigator.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 20),
          Expanded(child: Text(message)),
        ]),
      ),
    ),
  );
  try {
    return await task();
  } finally {
    nav.pop();
  }
}

/// Lit les couvertures sur le téléphone pour les inclure dans la sauvegarde.
Future<List<BackupEntry>> _entriesFor(Iterable<Item> items) async {
  final entries = <BackupEntry>[];
  for (final item in items) {
    List<int>? cover;
    final path = item.coverPath;
    if (!kIsWeb && path != null) {
      final f = File(path);
      if (await f.exists()) cover = await f.readAsBytes();
    }
    entries.add(BackupEntry(
      item.copyWith(id: null, coverPath: null),
      cover: cover,
      coverExtension: path == null || p.extension(path).isEmpty ? '.jpg' : p.extension(path),
    ));
  }
  return entries;
}

Uint8List _encode(List<BackupEntry> entries) => encodeBackup(entries);

String _plural(int n, String one, String many) => '$n ${n > 1 ? many : one}';

// ---------------------------------------------------------------------------

Future<void> exportBackup(BuildContext context) async {
  final library = LibraryScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  if (library.items.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Rien à sauvegarder : la bibliothèque est vide.')));
    return;
  }
  final count = library.items.length;
  try {
    final bytes = await _withProgress(context, 'Préparation de la sauvegarde…', () async {
      // La compression se fait en arrière-plan pour ne pas figer l'écran.
      return compute(_encode, await _entriesFor(library.items));
    });
    final uri = await FilePicker.saveFile(
      fileName: backupFileName(DateTime.now()),
      bytes: bytes,
      mimeType: 'application/zip',
      dialogTitle: 'Enregistrer la sauvegarde',
    );
    if (uri == null && !kIsWeb) return; // L'utilisateur a annulé.
    messenger.showSnackBar(SnackBar(
      content: Text('Sauvegarde enregistrée : ${_plural(count, 'objet', 'objets')}.'),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('La sauvegarde a échoué : $e')));
  }
}

enum _Mode { merge, replace }

Future<void> importBackup(BuildContext context) async {
  final library = LibraryScope.read(context);
  final messenger = ScaffoldMessenger.of(context);

  final PlatformFile? file;
  try {
    file = await FilePicker.pickFile(dialogTitle: 'Choisir une sauvegarde');
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Impossible d\'ouvrir le fichier : $e')));
    return;
  }
  if (file == null || !context.mounted) return;

  BackupContents contents;
  try {
    contents = await _withProgress(
        context, 'Lecture de la sauvegarde…', () async => compute(decodeBackup, await file!.readAsBytes()));
  } on BackupException catch (e) {
    if (context.mounted) await _showError(context, e.message);
    return;
  } catch (_) {
    if (context.mounted) await _showError(context, 'Le fichier n\'a pas pu être lu.');
    return;
  }
  if (!context.mounted) return;
  if (contents.entries.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text('Cette sauvegarde ne contient aucun objet.')));
    return;
  }

  final toAdd = newEntries(library.items, contents.entries);
  final mode = await _askMode(context, contents, current: library.items.length, newCount: toAdd.length);
  if (mode == null || !context.mounted) return;

  if (mode == _Mode.merge && toAdd.isEmpty) {
    messenger.showSnackBar(const SnackBar(
        content: Text('Rien de nouveau : tous les objets de la sauvegarde sont déjà dans votre bibliothèque.')));
    return;
  }

  try {
    if (mode == _Mode.replace) {
      // Copie de l'état actuel, gardée en mémoire pour pouvoir annuler.
      final previous = await _entriesFor(library.items);
      if (!context.mounted) return;
      await _withProgress(context, 'Restauration…', () => _apply(library, contents.entries, replace: true));
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Bibliothèque restaurée : ${_plural(contents.entries.length, 'objet', 'objets')}.'),
        action: previous.isEmpty
            ? null
            : SnackBarAction(label: 'Annuler', onPressed: () => _apply(library, previous, replace: true)),
      ));
    } else {
      if (!context.mounted) return;
      final added = await _withProgress(context, 'Ajout…', () => _apply(library, toAdd, replace: false));
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('${_plural(added.length, 'objet ajouté', 'objets ajoutés')} à votre bibliothèque.'),
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            for (final item in added) {
              await library.remove(item);
              await deleteCoverFile(item.coverPath);
            }
          },
        ),
      ));
    }
  } catch (e) {
    if (context.mounted) await _showError(context, 'La restauration a échoué, votre bibliothèque n\'a pas changé.\n($e)');
  }
}

/// Écrit les couvertures puis enregistre les objets. En cas d'échec, rien ne change.
Future<List<Item>> _apply(Library library, List<BackupEntry> entries, {required bool replace}) async {
  final oldCovers = replace ? library.items.map((i) => i.coverPath).whereType<String>().toList() : <String>[];
  final written = <String>[];
  final List<Item> saved;
  try {
    final items = <Item>[];
    for (final e in entries) {
      String? path;
      if (!kIsWeb && e.cover != null) {
        path = await saveCoverBytes(e.cover!, e.coverExtension);
        written.add(path);
      }
      items.add(e.item.copyWith(id: null, coverPath: path));
    }
    saved = await library.restore(items, replace: replace);
  } catch (_) {
    for (final w in written) {
      await deleteCoverFile(w);
    }
    rethrow;
  }
  // Les anciennes images ne sont supprimées qu'une fois la restauration réussie.
  for (final c in oldCovers) {
    await deleteCoverFile(c);
  }
  return saved;
}

Future<_Mode?> _askMode(BuildContext context, BackupContents c, {required int current, required int newCount}) async {
  final theme = Theme.of(context);
  final parts = [
    for (final t in ItemType.values)
      if (c.count(t) > 0)
        t == ItemType.bd ? '${c.count(t)} BD' : _plural(c.count(t), t.label.toLowerCase(), t.plural.toLowerCase()),
    if (c.wishlistCount > 0) _plural(c.wishlistCount, 'envie', 'envies'),
  ];
  final already = c.entries.length - newCount;
  final mode = await showDialog<_Mode>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.restore),
      title: const Text('Restaurer la sauvegarde ?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Sauvegarde du ${DateFormat.yMMMMd('fr').add_Hm().format(c.createdAt)}',
            style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        Text('${_plural(c.entries.length, 'objet', 'objets')} : ${parts.join(' · ')}'),
        if (current > 0) ...[
          const SizedBox(height: 16),
          Text(newCount == 0
              ? 'Tous ces objets sont déjà dans votre bibliothèque : une fusion n\'ajouterait rien.'
              : 'Fusionner ajoute ${_plural(newCount, 'objet', 'objets')} à votre bibliothèque'
                  '${already > 0 ? ' (${_plural(already, 'est déjà présent', 'sont déjà présents')})' : ''}.'),
          const SizedBox(height: 8),
          Text('Remplacer efface vos ${_plural(current, 'objet actuel', 'objets actuels')} '
              'et les remplace par la sauvegarde.'),
        ],
      ]),
      actions: current == 0
          ? [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              FilledButton(onPressed: () => Navigator.pop(ctx, _Mode.replace), child: const Text('Restaurer')),
            ]
          : [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuler')),
              if (newCount == 0)
                FilledButton(onPressed: () => Navigator.pop(ctx, _Mode.replace), child: const Text('Remplacer'))
              else ...[
                TextButton(onPressed: () => Navigator.pop(ctx, _Mode.replace), child: const Text('Remplacer')),
                FilledButton(onPressed: () => Navigator.pop(ctx, _Mode.merge), child: const Text('Fusionner')),
              ],
            ],
    ),
  );
  if (mode != _Mode.replace || current == 0 || !context.mounted) return mode;

  // Remplacer efface des données : on demande confirmation.
  final sure = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Remplacer toute la bibliothèque ?'),
      content: Text('Vos ${_plural(current, 'objet actuel sera supprimé', 'objets actuels seront supprimés')}. '
          'Vous pourrez annuler juste après, depuis le message en bas de l\'écran.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remplacer')),
      ],
    ),
  );
  return sure == true ? _Mode.replace : null;
}

Future<void> _showError(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error_outline),
        title: const Text('Restauration impossible'),
        content: Text(message),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
