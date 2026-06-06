import 'dart:convert';

import 'package:calcwise_core/calcwise_core.dart' show DatabaseAdapter;
import 'database_service.dart';

/// DatabaseAdapter implementation for HELOCApp.
///
/// Bridges SmartHistoryService (which speaks HistoryEntry / l1_json / l2_json)
/// to HELOCApp's `history` table, which stores `inputs` / `results` JSON blobs.
///
/// `app_key` / `screen_id` are always 'helocapp' / 'calculator' for this app.
class HelocDatabaseAdapter implements DatabaseAdapter {
  static const _appKey = 'helocapp';
  static const _screenId = 'calculator';

  // ── Insert ──────────────────────────────────────────────────────────────────

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final l2 = jsonDecode(row['l2_json'] as String) as Map<String, dynamic>;
    final savedAt = DateTime.fromMillisecondsSinceEpoch(row['saved_at'] as int);

    final inputs = (l2['inputs'] as Map?)?.cast<String, dynamic>() ?? {};
    final results = (l2['results'] as Map?)?.cast<String, dynamic>() ?? {};

    return DatabaseService.instance.insertHistory(
      inputs: inputs,
      results: results,
      createdAt: savedAt,
      inputHash: row['result_hash'] as String?,
      isPinned: (row['is_pinned'] as int?) ?? 0,
      pinLabel: row['pin_label'] as String?,
      pinOrder: (row['pin_order'] as int?) ?? 0,
      l1Json: row['l1_json'] as String?,
    );
  }

  // ── Query ────────────────────────────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    final db = await DatabaseService.instance.database;
    String? where;
    List<dynamic>? whereArgs;
    if (isPinned != null) {
      where = 'is_pinned = ?';
      whereArgs = [isPinned ? 1 : 0];
    }
    final rows = await db.query(
      'history',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'is_pinned DESC, pin_order DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({
    required String appKey,
    required String resultHash,
  }) async {
    final row = await DatabaseService.instance.getHistoryByHash(resultHash);
    return row == null ? null : _toAdapterRow(row);
  }

  // ── Update / Delete ──────────────────────────────────────────────────────────

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    return DatabaseService.instance.updateHistoryEntry(id, values);
  }

  @override
  Future<int> deleteRow(int id) async {
    await DatabaseService.instance.deleteHistory(id);
    return 1;
  }

  // ── Count / Eviction ─────────────────────────────────────────────────────────

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async {
    return DatabaseService.instance.countHistory(isPinned: isPinned);
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({
    required String appKey,
    required int limit,
  }) async {
    final rows = await DatabaseService.instance.getOldestAutoSaves(limit);
    return rows.map(_toAdapterRow).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({
    required String appKey,
    required int limit,
  }) async {
    final rows = await DatabaseService.instance.getOldestPinnedEntries(limit);
    return rows.map(_toAdapterRow).toList();
  }

  // ── Mapping ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toAdapterRow(Map<String, dynamic> row) {
    final createdAt = DateTime.tryParse(row['created_at'] as String? ?? '')
            ?.millisecondsSinceEpoch ??
        0;
    final inputs = _decode(row['inputs']);
    final results = _decode(row['results']);
    final l1Json =
        (row['l1_json'] as String?) ?? _buildDefaultL1Json(inputs, results);
    final l2Json = jsonEncode({'inputs': inputs, 'results': results});
    return {
      'id': row['id'],
      'app_key': _appKey,
      'screen_id': _screenId,
      'result_hash': (row['input_hash'] as String?) ?? '',
      'l1_json': l1Json,
      'l2_json': l2Json,
      'saved_at': createdAt,
      'is_pinned': (row['is_pinned'] as int?) ?? 0,
      'pin_label': row['pin_label'],
      'pin_order': (row['pin_order'] as int?) ?? 0,
    };
  }

  Map<String, dynamic> _decode(dynamic value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.isNotEmpty) {
      return (jsonDecode(value) as Map).cast<String, dynamic>();
    }
    return {};
  }

  String _buildDefaultL1Json(
      Map<String, dynamic> inputs, Map<String, dynamic> results) {
    return jsonEncode({
      'draw': (inputs['draw'] as num?)?.toDouble() ?? 0.0,
      'rate': (inputs['rate'] as num?)?.toDouble() ?? 0.0,
      'interestOnly': (results['interestOnly'] as num?)?.toDouble() ?? 0.0,
    });
  }
}
