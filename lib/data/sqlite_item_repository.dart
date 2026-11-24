import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/item.dart';
import 'item_repository.dart';

class SqliteItemRepository implements ItemRepository {
  SqliteItemRepository._(this._db);

  final Database _db;

  static Future<SqliteItemRepository> open() async {
    final path = p.join(await getDatabasesPath(), 'bibliotheque.db');
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) => db.execute('''
        CREATE TABLE items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          type TEXT NOT NULL,
          title TEXT NOT NULL,
          creator TEXT NOT NULL DEFAULT '',
          year INTEGER,
          publisher TEXT NOT NULL DEFAULT '',
          series TEXT NOT NULL DEFAULT '',
          volume TEXT NOT NULL DEFAULT '',
          genre TEXT NOT NULL DEFAULT '',
          format TEXT NOT NULL DEFAULT '',
          identifier TEXT NOT NULL DEFAULT '',
          condition TEXT,
          rating INTEGER NOT NULL DEFAULT 0,
          wishlist INTEGER NOT NULL DEFAULT 0,
          loaned_to TEXT,
          loan_date INTEGER,
          notes TEXT NOT NULL DEFAULT '',
          cover_path TEXT,
          created_at INTEGER NOT NULL
        )
      '''),
    );
    return SqliteItemRepository._(db);
  }

  @override
  Future<List<Item>> all() async {
    final rows = await _db.query('items');
    return rows.map(Item.fromMap).toList();
  }

  @override
  Future<Item> insert(Item item) async {
    final map = item.toMap()..remove('id');
    final id = await _db.insert('items', map);
    return item.copyWith(id: id);
  }

  @override
  Future<void> update(Item item) async {
    await _db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }

  @override
  Future<void> delete(int id) async {
    await _db.delete('items', where: 'id = ?', whereArgs: [id]);
  }
}
