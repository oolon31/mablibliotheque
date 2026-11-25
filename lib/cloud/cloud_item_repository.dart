import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../data/item_repository.dart';
import '../models/item.dart';
import 'covers.dart';

/// Bibliothèque hébergée sur le serveur. [ownerId] désigne la bibliothèque visée :
/// la sienne, ou celle d'une personne qui l'a partagée. Les règles du serveur décident
/// de ce qui est permis (lecture seule ou modification).
class CloudItemRepository implements ItemRepository {
  CloudItemRepository(this.ownerId);

  final String ownerId;

  SupabaseClient get _db => Supabase.instance.client;

  static const _select = '*, item_private(loaned_to, loan_date, notes)';

  @override
  Future<List<Item>> all() async {
    final rows = await _db.from('items').select(_select).eq('owner_id', ownerId).order('id');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Item> insert(Item item) async {
    final remote = isLocalCover(item.coverPath) ? await CloudCovers.upload(ownerId, item.coverPath!) : item.coverPath;
    int? id;
    try {
      final row = await _db.from('items').insert(_itemRow(item, remote)).select('id').single();
      id = row['id'] as int;
      await _db.from('item_private').upsert(_privateRow(id, item));
    } catch (e) {
      // Pas de demi-objet : on annule la ligne et la couverture envoyée.
      if (id != null) await _db.from('items').delete().eq('id', id);
      await CloudCovers.remove([if (remote != item.coverPath) remote]);
      rethrow;
    }
    _forgetLocal(item.coverPath);
    return item.copyWith(id: id, coverPath: remote);
  }

  @override
  Future<void> update(Item item) async {
    final id = item.id!;
    final old = await _db.from('items').select('cover_path').eq('id', id).maybeSingle();
    final oldCover = old?['cover_path'] as String?;
    final remote = isLocalCover(item.coverPath) ? await CloudCovers.upload(ownerId, item.coverPath!) : item.coverPath;

    await _db.from('items').update(_itemRow(item, remote)).eq('id', id);
    await _db.from('item_private').upsert(_privateRow(id, item));

    if (oldCover != remote) await CloudCovers.remove([oldCover]);
    _forgetLocal(item.coverPath);
  }

  @override
  Future<void> delete(int id) async {
    final row = await _db.from('items').select('cover_path').eq('id', id).maybeSingle();
    await _db.from('items').delete().eq('id', id);
    await CloudCovers.remove([row?['cover_path'] as String?]);
  }

  /// Restauration atomique (fonction restore_library) : tout réussit ou rien ne change.
  @override
  Future<List<Item>> insertAll(List<Item> items, {bool replace = false}) async {
    final oldCovers = replace
        ? (await _db.from('items').select('cover_path').eq('owner_id', ownerId))
              .map((r) => r['cover_path'] as String?)
              .toList()
        : <String?>[];

    final remotes = <String?>[];
    final uploaded = <String>[];
    try {
      final payload = <Map<String, Object?>>[];
      for (final i in items) {
        String? remote = i.coverPath;
        if (isLocalCover(i.coverPath)) {
          remote = await CloudCovers.upload(ownerId, i.coverPath!);
          uploaded.add(remote);
        }
        remotes.add(remote);
        payload.add({
          'type': i.type.name,
          'title': i.title,
          'creator': i.creator,
          'year': i.year,
          'publisher': i.publisher,
          'series': i.series,
          'volume': i.volume,
          'genre': i.genre,
          'format': i.format,
          'identifier': i.identifier,
          'condition': i.condition?.name,
          'rating': i.rating,
          'wishlist': i.wishlist,
          'loaned_to': i.isLoaned ? i.loanedTo : null,
          'loan_date': i.loanDate?.toUtc().toIso8601String(),
          'notes': i.notes,
          'cover_path': remote,
        });
      }
      final res = await _db.rpc('restore_library', params: {'payload': payload, 'replace_all': replace});
      final ids = (res as List).map((e) => (e as num).toInt()).toList();
      if (ids.length != items.length) throw StateError('réponse inattendue du serveur');

      await CloudCovers.remove(oldCovers);
      for (final i in items) {
        _forgetLocal(i.coverPath);
      }
      return [for (var k = 0; k < items.length; k++) items[k].copyWith(id: ids[k], coverPath: remotes[k])];
    } catch (_) {
      await CloudCovers.remove(uploaded);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------

  Map<String, Object?> _itemRow(Item i, String? cover) => {
    'owner_id': ownerId,
    'type': i.type.name,
    'title': i.title,
    'creator': i.creator,
    'year': i.year,
    'publisher': i.publisher,
    'series': i.series,
    'volume': i.volume,
    'genre': i.genre,
    'format': i.format,
    'identifier': i.identifier,
    'condition': i.condition?.name,
    'rating': i.rating,
    'wishlist': i.wishlist,
    'on_loan': i.isLoaned,
    'cover_path': cover,
    'updated_at': DateTime.now().toUtc().toIso8601String(),
  };

  Map<String, Object?> _privateRow(int id, Item i) => {
    'item_id': id,
    'owner_id': ownerId,
    'loaned_to': i.isLoaned && !i.onLoanHidden ? i.loanedTo : null,
    'loan_date': i.loanDate?.toUtc().toIso8601String(),
    'notes': i.notes,
  };

  Item _fromRow(Map<String, dynamic> r) {
    final priv = r['item_private'];
    final Map<String, dynamic>? pm = switch (priv) {
      Map() => Map<String, dynamic>.from(priv),
      List() when priv.isNotEmpty => Map<String, dynamic>.from(priv.first as Map),
      _ => null,
    };
    final loanedTo = pm?['loaned_to'] as String?;
    final conditionName = r['condition'] as String?;
    final loanDate = pm?['loan_date'] as String?;
    return Item(
      id: r['id'] as int,
      type: ItemType.values.byName(r['type'] as String),
      title: r['title'] as String,
      creator: (r['creator'] as String?) ?? '',
      year: r['year'] as int?,
      publisher: (r['publisher'] as String?) ?? '',
      series: (r['series'] as String?) ?? '',
      volume: (r['volume'] as String?) ?? '',
      genre: (r['genre'] as String?) ?? '',
      format: (r['format'] as String?) ?? '',
      identifier: (r['identifier'] as String?) ?? '',
      condition: conditionName == null ? null : ItemCondition.values.byName(conditionName),
      rating: (r['rating'] as int?) ?? 0,
      wishlist: (r['wishlist'] as bool?) ?? false,
      loanedTo: loanedTo,
      loanDate: loanDate == null ? null : DateTime.parse(loanDate).toLocal(),
      notes: (pm?['notes'] as String?) ?? '',
      coverPath: r['cover_path'] as String?,
      createdAt: DateTime.parse(r['created_at'] as String).toLocal(),
      // Sans ligne privée (lecteur), on sait seulement que l'objet est prêté.
      onLoanHidden: pm == null && (r['on_loan'] as bool? ?? false),
    );
  }

  /// Supprime la copie locale d'une image une fois envoyée.
  void _forgetLocal(String? path) {
    if (!isLocalCover(path)) return;
    try {
      File(path!).deleteSync();
    } catch (_) {}
  }
}
