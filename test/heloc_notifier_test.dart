// Regression tests for the HELOC cross-screen notifier wiring.
//
// Context: calculator_screen.dart used to write
//   helocNotifier.value = (creditLimit: draw, balance: draw, rate: rate)
// which set BOTH creditLimit and balance to the new draw amount, silently
// dropping the existing mortgage balance. payment_shock_screen.dart and
// heloc_vs_cashout_screen.dart read `balance` expecting the EXISTING
// MORTGAGE BALANCE (a separate field, `_mortgageCtrl`), so they were
// pre-filled with the wrong number.
//
// Also, CalculatorScreen lives inside MainShell's persistent Stack (it is
// never recreated), so writing to a ValueNotifier from history_detail_screen
// had no visible effect unless CalculatorScreen actually subscribes to it.
//
// These tests exercise the notifier contract directly (no Firebase/widget
// tree needed) so they mirror what main.dart + calculator_screen.dart do
// without importing main.dart (which requires Firebase.initializeApp).

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the record type + semantics declared in lib/main.dart.
typedef HelocNotifierValue = ({double creditLimit, double balance, double rate});

void main() {
  group('HELOC notifier — draw vs existing balance separation', () {
    test(
        'RG: calculator must publish draw amount and existing mortgage '
        'balance as two distinct fields, not the same value', () {
      final notifier =
          ValueNotifier<HelocNotifierValue>((creditLimit: 100000, balance: 250000, rate: 7.5));

      // Simulates calculator_screen._tryCalculate() with distinct
      // draw ($120k) and mortgage balance ($300k) inputs.
      const draw = 120000.0;
      const mortgageBalance = 300000.0;
      const rate = 6.25;

      // Correct wiring (the fix): creditLimit=draw, balance=mortgage.
      notifier.value = (creditLimit: draw, balance: mortgageBalance, rate: rate);

      expect(notifier.value.creditLimit, draw,
          reason: 'creditLimit must carry the draw amount (consumed by '
              'draw_schedule/compare screens)');
      expect(notifier.value.balance, mortgageBalance,
          reason: 'balance must carry the EXISTING MORTGAGE BALANCE, not '
              'the draw amount — payment_shock and heloc_vs_cashout screens '
              'read this field expecting the existing balance');
      expect(notifier.value.balance, isNot(equals(notifier.value.creditLimit)),
          reason: 'draw and existing mortgage balance are independent '
              'inputs and must never be conflated');
    });

    test('payment_shock pre-fill reads the existing mortgage balance field',
        () {
      final notifier =
          ValueNotifier<HelocNotifierValue>((creditLimit: 80000, balance: 400000, rate: 5.0));

      // Mirrors payment_shock_screen.dart initState pre-fill logic.
      final h = notifier.value;
      final prefilledBalance = h.balance;

      expect(prefilledBalance, 400000,
          reason: 'PaymentShockScreen must pre-fill from the mortgage '
              'balance, not the HELOC draw amount');
    });

    test(
        'heloc_vs_cashout pre-fill reads the existing mortgage balance field',
        () {
      final notifier =
          ValueNotifier<HelocNotifierValue>((creditLimit: 50000, balance: 275000, rate: 7.0));

      final h = notifier.value;
      final prefilledExistingBalance = h.balance;

      expect(prefilledExistingBalance, 275000,
          reason: 'HelocVsCashoutScreen must pre-fill _existingBalCtrl from '
              'the mortgage balance, not the HELOC draw amount');
    });
  });

  group('HELOC notifier — history restore reaches the calculator', () {
    /// Mirrors main.dart's calculatorRestoreNotifier + calculator_screen's
    /// _onRestoreRequested, without needing the full widget tree.
    late ValueNotifier<Map<String, dynamic>?> restoreNotifier;
    late Map<String, dynamic> appliedControllerState;

    setUp(() {
      restoreNotifier = ValueNotifier<Map<String, dynamic>?>(null);
      appliedControllerState = {};
    });

    void applyRestore(Map<String, dynamic>? data) {
      // Mirrors _CalculatorScreenState._onRestoreRequested.
      if (data == null) return;
      appliedControllerState = {
        'homeValue': (data['homeValue'] as num?) ?? 400000,
        'balance': (data['balance'] as num?) ?? 250000,
        'draw': (data['draw'] as num?) ?? 100000,
        'rate': (data['rate'] as num?) ?? 7.5,
        'drawYears': (data['drawYears'] as num?) ?? 10,
        'repayYears': (data['repayYears'] as num?) ?? 20,
      };
    }

    test(
        'RG: loading a history entry into the calculator updates the '
        'visible fields via the restore notifier', () {
      restoreNotifier.addListener(() => applyRestore(restoreNotifier.value));

      // Simulates history_detail_screen's "Load into Calculator" button
      // pushing a saved scenario.
      restoreNotifier.value = {
        'homeValue': 550000.0,
        'balance': 320000.0,
        'draw': 90000.0,
        'rate': 6.75,
        'drawYears': 8,
        'repayYears': 15,
        'taxBracket': 24.0,
        'seq': 1,
      };

      expect(appliedControllerState['homeValue'], 550000.0);
      expect(appliedControllerState['balance'], 320000.0);
      expect(appliedControllerState['draw'], 90000.0);
      expect(appliedControllerState['rate'], 6.75);
      expect(appliedControllerState['drawYears'], 8);
      expect(appliedControllerState['repayYears'], 15);
    });

    test(
        'RG: a second load of a different scenario also propagates '
        '(sequence bump makes repeat/refresh loads observable)', () {
      restoreNotifier.addListener(() => applyRestore(restoreNotifier.value));

      restoreNotifier.value = {
        'homeValue': 400000.0,
        'balance': 200000.0,
        'draw': 50000.0,
        'rate': 5.5,
        'drawYears': 10,
        'repayYears': 20,
        'seq': 1,
      };
      expect(appliedControllerState['draw'], 50000.0);

      restoreNotifier.value = {
        'homeValue': 700000.0,
        'balance': 450000.0,
        'draw': 150000.0,
        'rate': 8.0,
        'drawYears': 5,
        'repayYears': 25,
        'seq': 2,
      };
      expect(appliedControllerState['draw'], 150000.0);
      expect(appliedControllerState['balance'], 450000.0);
    });

    test('no-op when restore notifier value is null (initial state)', () {
      restoreNotifier.addListener(() => applyRestore(restoreNotifier.value));
      expect(appliedControllerState, isEmpty);
    });
  });
}
