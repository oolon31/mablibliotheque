import 'package:material_ui/material_ui.dart';

import '../models/item.dart';
import '../services/barcode.dart';
import '../services/catalog_lookup.dart';
import '../state/library.dart';
import '../widgets/cover.dart';
import 'item_detail_screen.dart';
import 'item_form_screen.dart';
import 'scanner_screen.dart';

/// Résultat d'une recherche : la fiche (si trouvée), la couverture téléchargée, et un message.
class LookupOutcome {
  const LookupOutcome({this.result, this.coverPath, this.error});
  final LookupResult? result;
  final String? coverPath;
  final String? error;

  String message() {
    if (error != null) return 'Recherche impossible ($error). Complétez la fiche à la main.';
    if (result == null) return 'Aucune fiche trouvée pour ce code. Complétez-la à la main.';
    return 'Fiche trouvée sur ${result!.source}. Vérifiez-la avant d\'enregistrer.';
  }
}

/// Ouvre le lecteur de code-barres et renvoie le code lu, ou null.
Future<String?> scanCode(BuildContext context) =>
    Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const ScannerScreen()));

Future<LookupOutcome> _fetch(String code) async {
  final lookup = CatalogLookup();
  LookupResult? result;
  try {
    result = await lookup.lookup(code);
  } on LookupException catch (e) {
    return LookupOutcome(error: e.message);
  } catch (_) {
    // Réponse inattendue d'un serveur : on ne bloque pas l'ajout pour autant.
    return const LookupOutcome(error: 'réponse illisible du serveur');
  }
  final candidates = [
    if (result?.coverUrl != null) result!.coverUrl!,
    if (isIsbn(code)) 'https://covers.openlibrary.org/b/isbn/$code-L.jpg?default=false',
  ];
  String? coverPath;
  for (final url in candidates) {
    final bytes = await lookup.downloadImage(url);
    if (bytes != null) {
      try {
        coverPath = await saveCoverBytes(bytes);
      } catch (_) {}
      break;
    }
  }
  return LookupOutcome(result: result, coverPath: coverPath);
}

/// Cherche la fiche en affichant une fenêtre d'attente. Renvoie null si l'utilisateur annule.
Future<LookupOutcome?> lookupWithProgress(BuildContext context, String code) async {
  final nav = Navigator.of(context);
  var cancelled = false;
  var finished = false;
  final future = _fetch(code);
  final dialog = showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      content: Row(children: [
        const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3)),
        const SizedBox(width: 20),
        Expanded(child: Text('Recherche du code\n$code…')),
      ]),
      actions: [
        TextButton(
          onPressed: () {
            cancelled = true;
            Navigator.pop(ctx);
          },
          child: const Text('Annuler'),
        ),
      ],
    ),
  );
  await Future.any([future.whenComplete(() => finished = true), dialog]);
  if (cancelled) {
    // La couverture éventuellement téléchargée ne servira pas.
    future.then((o) => deleteCoverFile(o.coverPath));
    return null;
  }
  if (finished) nav.pop();
  return future;
}

Item draftFromLookup(String code, LookupOutcome outcome, {bool wishlist = false}) {
  final r = outcome.result;
  return Item(
    type: r?.type ?? guessTypeFromCode(code),
    title: r?.title ?? '',
    creator: r?.creator ?? '',
    year: r?.year,
    publisher: r?.publisher ?? '',
    series: r?.series ?? '',
    volume: r?.volume ?? '',
    genre: r?.genre ?? '',
    format: r?.format ?? '',
    identifier: code,
    coverPath: outcome.coverPath,
    wishlist: wishlist,
    createdAt: DateTime.now(),
  );
}

/// Ajout par code-barres : lecture, détection des doublons, recherche, puis formulaire prérempli.
Future<void> scanAndAdd(BuildContext context, {bool wishlist = false}) async {
  final library = LibraryScope.read(context);
  final nav = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  final code = await scanCode(context);
  if (code == null || !context.mounted) return;

  final existing = library.items.where((i) => i.identifier.isNotEmpty && sameCode(i.identifier, code)).firstOrNull;
  if (existing != null) {
    final choice = await _askDuplicate(context, existing);
    if (choice == null || !context.mounted) return;
    if (choice == _Duplicate.open) {
      nav.push(MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(itemId: existing.id!)));
      return;
    }
  }

  final outcome = await lookupWithProgress(context, code);
  if (outcome == null || !context.mounted) return;
  nav.push(MaterialPageRoute<void>(
    builder: (_) => ItemFormScreen(draft: draftFromLookup(code, outcome, wishlist: wishlist)),
  ));
  messenger.showSnackBar(SnackBar(content: Text(outcome.message()), duration: const Duration(seconds: 5)));
}

enum _Duplicate { open, addAnyway }

Future<_Duplicate?> _askDuplicate(BuildContext context, Item existing) {
  final where = existing.wishlist ? 'dans votre liste d\'envies' : 'dans votre collection';
  return showDialog<_Duplicate>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.info_outline),
      title: const Text('Vous l\'avez déjà'),
      content: Row(children: [
        Cover(item: existing, width: 48),
        const SizedBox(width: 16),
        Expanded(child: Text('« ${existing.title} » est déjà $where.')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, _Duplicate.addAnyway), child: const Text('Ajouter un exemplaire')),
        FilledButton(onPressed: () => Navigator.pop(ctx, _Duplicate.open), child: const Text('Voir la fiche')),
      ],
    ),
  );
}
