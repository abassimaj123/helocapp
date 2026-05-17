import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:calcwise_core/calcwise_core.dart' show MonetizationConfig;
import '../freemium/freemium_service.dart';

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
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            inputs TEXT NOT NULL,
            results TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        // Future schema migrations go here
      },
    );
  }

  /// Insert a calculation. Enforces free-tier limit (max 5).
  Future<void> insertHistory({
    required Map<String, dynamic> inputs,
    required Map<String, dynamic> results,
  }) async {
    final db = await database;
    await db.insert('history', {
      'inputs': jsonEncode(inputs),
      'results': jsonEncode(results),
      'created_at': DateTime.now().toIso8601String(),
    });

    if (!freemiumService.hasFullAccess) {
      final all = await db.query('history', orderBy: 'created_at DESC');
      if (all.length > MonetizationConfig.freeCalculationLimit) {
        final idsToDelete = all
            .skip(MonetizationConfig.freeCalculationLimit)
            .map((r) => r['id'] as int)
            .toList();
        for (final id in idsToDelete) {
          await db.delete('history', where: 'id = ?', whereArgs: [id]);
        }
      }
    }
  }

  Future<List<Map<String, dynamic>>> getHistory() async {
    final db = await database;
    final rows = await db.query('history', orderBy: 'created_at DESC');
    return rows.map((r) {
      return {
        'id': r['id'],
        'inputs': jsonDecode(r['inputs'] as String) as Map<String, dynamic>,
        'results': jsonDecode(r['results'] as String) as Map<String, dynamic>,
        'created_at': r['created_at'],
      };
    }).toList();
  }

  Future<void> deleteHistory(int id) async {
    final db = await database;
    await db.delete('history', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearHistory() async {
    final db = await database;
    await db.delete('history');
  }
}
