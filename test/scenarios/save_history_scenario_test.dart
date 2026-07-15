import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:calcwise_core/calcwise_core.dart';

class _MemoryAdapter implements DatabaseAdapter {
  final List<Map<String, dynamic>> _rows = [];
  int _nextId = 1;
  int get rowCount => _rows.length;

  @override
  Future<int> insertRow(Map<String, dynamic> row) async {
    final id = _nextId++;
    _rows.add({...row, 'id': id});
    return id;
  }

  @override
  Future<List<Map<String, dynamic>>> getRows({
    required String appKey,
    String? screenId,
    bool? isPinned,
    int? limit,
  }) async {
    var result = _rows.where((r) {
      if (r['app_key'] != appKey) return false;
      if (screenId != null && r['screen_id'] != screenId) return false;
      if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
      return true;
    }).toList();
    result.sort((a, b) {
      final aPin = a['is_pinned'] as int;
      final bPin = b['is_pinned'] as int;
      if (aPin != bPin) return bPin.compareTo(aPin);
      return (b['saved_at'] as int).compareTo(a['saved_at'] as int);
    });
    if (limit != null && result.length > limit) result = result.sublist(0, limit);
    return result;
  }

  @override
  Future<Map<String, dynamic>?> getRowByHash({required String appKey, required String screenId, required String resultHash}) async {
    try { return _rows.firstWhere((r) => r['app_key'] == appKey && r['screen_id'] == screenId && r['result_hash'] == resultHash); }
    catch (_) { return null; }
  }

  @override
  Future<int> updateRow(int id, Map<String, dynamic> values) async {
    final idx = _rows.indexWhere((r) => r['id'] == id);
    if (idx < 0) return 0;
    _rows[idx] = {..._rows[idx], ...values};
    return 1;
  }

  @override
  Future<int> deleteRow(int id) async {
    final before = _rows.length;
    _rows.removeWhere((r) => r['id'] == id);
    return before - _rows.length;
  }

  @override
  Future<int> countRows({required String appKey, bool? isPinned}) async =>
      _rows.where((r) {
        if (r['app_key'] != appKey) return false;
        if (isPinned != null) return ((r['is_pinned'] as int) == 1) == isPinned;
        return true;
      }).length;

  @override
  Future<List<Map<String, dynamic>>> getOldestAutoSaves({required String appKey, required int limit}) async {
    final rows = _rows.where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 0).toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }

  @override
  Future<List<Map<String, dynamic>>> getOldestPinned({required String appKey, required int limit}) async {
    final rows = _rows.where((r) => r['app_key'] == appKey && (r['is_pinned'] as int) == 1).toList()
      ..sort((a, b) => (a['saved_at'] as int).compareTo(b['saved_at'] as int));
    return rows.take(limit).toList();
  }
}

Future<void> _pump() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  late _MemoryAdapter adapter;
  late CalcwiseFreemium freemium;
  late SmartHistoryService svc;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    adapter = _MemoryAdapter();
    freemium = CalcwiseFreemium(appKey: 'helocapp');
    await freemium.initialize();
    svc = SmartHistoryService(
      db: adapter,
      freemium: freemium,
      overrideSaveDebounce: Duration.zero,
    );
  });

  tearDown(() => svc.dispose());

  group('HELOCApp — save → history scenarios', () {
    test('scenario: calculate HELOC → entry appears in history', () async {
      // GIVEN: typical HELOC inputs (mirrors _buildL1/_buildL2 in calculator_screen.dart)
      const homeValue = 600000.0;
      const mortgageBalance = 350000.0;
      const drawAmount = 80000.0;
      const rate = 8.5;
      const drawYears = 10;
      const repayYears = 20;
      const interestOnly = 566.67;      // draw * rate / 12
      const monthlyPayment = 698.0;

      final inputHash = ResultHasher.hashMixed({
        'draw': ResultHasher.roundTo(drawAmount, 500),
        'rate': ResultHasher.roundTo(rate, 0.25),
        'drawYears': drawYears.toDouble(),
        'repayYears': repayYears.toDouble(),
      });

      // WHEN: auto-save triggered (mirrors calculator_screen._scheduleAutoSave)
      var savedCalled = false;
      svc.scheduleAutoSave(
        appKey: 'helocapp',
        screenId: 'calculator',
        inputHash: inputHash,
        l1: {
          'draw_amount': drawAmount,
          'rate': rate,
          'interest_only': interestOnly,
          'monthly_payment': monthlyPayment,
          'total_interest': 47520.0,
        },
        l2: {
          'inputs': {
            'homeValue': homeValue,
            'balance': mortgageBalance,
            'draw': drawAmount,
            'rate': rate,
            'drawYears': drawYears,
            'repayYears': repayYears,
          },
          'results': {
            'interestOnly': interestOnly,
            'repayment': monthlyPayment,
            'totalInterest': 47520.0,
          },
        },
        onSaved: () => savedCalled = true,
      );
      await _pump();

      // THEN
      final history = await svc.getHistory('helocapp');
      expect(history, isNotEmpty,
          reason: 'History must contain the HELOC entry');
      expect(history.first.l1['draw_amount'], drawAmount);
      expect(savedCalled, isTrue,
          reason: 'onSaved must fire — anti-regression for history refresh race condition');
    });

    test('scenario: two different draw amounts → both entries in history', () async {
      for (var i = 0; i < 2; i++) {
        final draw = 50000.0 + i * 30000;
        svc.scheduleAutoSave(
          appKey: 'helocapp',
          screenId: 'calculator',
          inputHash: 'hash-heloc-$i',
          l1: {'draw_amount': draw, 'rate': 8.5, 'monthly_payment': draw * 0.01},
          l2: {
            'inputs': {'homeValue': 600000.0, 'draw': draw, 'rate': 8.5},
            'results': {'repayment': draw * 0.01},
          },
        );
        await _pump();
      }
      final history = await svc.getHistory('helocapp');
      expect(history.length, 2);
    });

    test('scenario: same inputs twice → only one history entry', () async {
      const hash = 'same-hash-helocapp';
      for (var i = 0; i < 3; i++) {
        svc.scheduleAutoSave(
          appKey: 'helocapp',
          screenId: 'calculator',
          inputHash: hash,
          l1: {'draw_amount': 60000.0, 'rate': 8.0, 'monthly_payment': 550.0},
          l2: {
            'inputs': {'homeValue': 550000.0, 'draw': 60000.0, 'rate': 8.0},
            'results': {'repayment': 550.0},
          },
        );
        await _pump();
      }
      expect(adapter.rowCount, 1,
          reason: 'Identical inputs must not create duplicates');
    });

    test('scenario: pinned HELOC survives ring buffer eviction', () async {
      await svc.saveScenario(
        appKey: 'helocapp',
        screenId: 'calculator',
        inputHash: 'pinned-heloc-scenario',
        l1: {'draw_amount': 100000.0, 'rate': 7.5, 'monthly_payment': 750.0},
        l2: {
          'inputs': {'homeValue': 800000.0, 'draw': 100000.0, 'rate': 7.5},
          'results': {'repayment': 750.0},
        },
        label: 'Kitchen reno draw',
      );
      for (var i = 0; i < MonetizationConfig.freeRingBufferSize + 2; i++) {
        svc.scheduleAutoSave(
          appKey: 'helocapp',
          screenId: 'calculator',
          inputHash: 'auto-heloc-$i',
          l1: {'draw_amount': i * 5000.0, 'rate': 8.5},
          l2: {'inputs': {'draw': i * 5000.0}, 'results': <String, double>{}},
        );
        await _pump();
      }
      final pinned = await svc.getPinned('helocapp');
      expect(pinned, isNotEmpty,
          reason: 'Pinned HELOC scenario must survive ring buffer eviction');
      expect(pinned.first.l1['draw_amount'], 100000.0);
    });
  });
}
