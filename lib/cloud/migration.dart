import 'package:shared_preferences/shared_preferences.dart';

import '../data/sqlite_item_repository.dart';
import '../models/item.dart';

/// Import, une seule fois par compte, des objets enregistrés sur ce téléphone avant les comptes.
class LocalMigration {
  LocalMigration._();

  static String _key(String userId) => 'imported_$userId';

  static Future<List<Item>> pending(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_key(userId)) == true) return const [];
    try {
      final repo = await SqliteItemRepository.open();
      return await repo.all();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> markDone(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key(userId), true);
  }
}
