import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  DatabaseService._();
  static final DatabaseService instance = DatabaseService._();
  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final path = join(await getDatabasesPath(), 'heloc_app.db');
    return openDatabase(
      path,
      version: 2,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inputs TEXT NOT NULL,
            results TEXT NOT NULL,
            created_at TEXT NOT NULL,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            input_hash TEXT,
            pin_label TEXT,
            pin_order INTEGER NOT NULL DEFAULT 0,
            l1_json TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
              'ALTER TABLE history ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN input_hash TEXT');
          await db.execute('ALTER TABLE history ADD COLUMN pin_label TEXT');
          await db.execute(
              'ALTER TABLE history ADD COLUMN pin_order INTEGER NOT NULL DEFAULT 0');
          await db.execute('ALTER TABLE history ADD COLUMN l1_json TEXT');
        }
      },
    );
  }

  /// Insert a calculation row. Returns the new row id.
  ///
  /// Ring-buffer eviction is handled by SmartHistoryService, not here.
  Future<int> insertHistory({
    required Map<String, dynamic> inputs,
    required Map<String, dynamic> results,
    String? inputHash,
    int isPinned = 0,
    String? pinLabel,
    int pinOrder = 0,
    String? l1Json,
    DateTime? createdAt,
  }) async {
    final db = await database;
    return db.insert('history', {
      'inputs': jsonEncode(inputs),
      'results': jsonEncode(results),
      'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
      'input_hash': inputHash,
      'is_pinned': isPinned,
      'pin_label': pinLabel,
      'pin_order': pinOrder,
      'l1_json': l1Json,
    });
  }

  /// All history rows, pinned first then most-recent auto-saves.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await database;
    final rows = await db.query('history',
        orderBy: 'is_pinned DESC, pin_order DESC, created_at DESC');
    return rows.map(_decodeRow).toList();
  }

  Map<String, dynamic> _decodeRow(Map<String, dynamic> r) {
    return {
      'id': r['id'],
      'inputs': jsonDecode(r['inputs'] as String) as Map<String, dynamic>,
      'results': jsonDecode(r['results'] as String) as Map<String, dynamic>,
      'created_at': r['created_at'],
      'is_pinned': r['is_pinned'] ?? 0,
      'input_hash': r['input_hash'],
      'pin_label': r['pin_label'],
      'pin_order': r['pin_order'] ?? 0,
      'l1_json': r['l1_json'],
    };
  }

  Future<Map<String, dynamic>?> getHistoryByHash(String hash) async {
    final db = await database;
    final rows = await db.query('history',
        where: 'input_hash = ?', whereArgs: [hash], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> updateHistoryEntry(int id, Map<String, dynamic> values) async {
    final db = await database;
    return db.update('history', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> countHistory({bool? isPinned}) async {
    final db = await database;
    final String sql;
    if (isPinned == null) {
      sql = 'SELECT COUNT(*) FROM history';
    } else {
      sql = 'SELECT COUNT(*) FROM history WHERE is_pinned = ${isPinned ? 1 : 0}';
    }
    final result = await db.rawQuery(sql);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getOldestAutoSaves(int limit) async {
    final db = await database;
    return db.query('history',
        where: 'is_pinned = 0', orderBy: 'created_at ASC', limit: limit);
  }

  Future<List<Map<String, dynamic>>> getOldestPinnedEntries(int limit) async {
    final db = await database;
    return db.query('history',
        where: 'is_pinned = 1',
        orderBy: 'pin_order ASC, created_at ASC',
        limit: limit);
  }

  Future<void> deleteHistory(int id) async {
    final db = await database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOldestHistory() async {
    final db = await database;
    await db.rawDelete(
      'DELETE FROM history WHERE id = (SELECT id FROM history WHERE is_pinned = 0 ORDER BY created_at ASC LIMIT 1)',
    );
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('history');
  }
}
