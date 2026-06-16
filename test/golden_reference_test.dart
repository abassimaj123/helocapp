// Golden reference tests — HELOCApp
// Focus: rate is PERCENT (8.0 not 0.08) + wrong-unit: 0.08 gives $0.67 instead of $666.67
// Sources: FDIC HELOC guidelines, 85% CLTV standard.

import 'package:flutter_test/flutter_test.dart';
import 'package:heloc_app/core/heloc_engine.dart';

void main() {
  void approx(double actual, double expected, {double tol = 1.0}) {
    expect(actual, closeTo(expected, tol),
        reason: 'Expected ~$expected, got $actual');
  }

  // ── availableEquity ───────────────────────────────────────────────────────

  group('HelocEngine.availableEquity — 85% LTV', () {
    test('HELOC-G1: \$500k home / \$200k mortgage → \$225k available', () {
      approx(HelocEngine.availableEquity(500000, 200000), 225000, tol: 1);
    });

    test('HELOC-G2: LTV already at 85% → \$0 available', () {
      approx(HelocEngine.availableEquity(500000, 425000), 0, tol: 1);
    });

    test('HELOC-G3: mortgage > 85% LTV → clamped to \$0 (not negative)', () {
      expect(HelocEngine.availableEquity(500000, 450000), 0.0);
    });
  });

  // ── interestOnlyPayment — rate is PERCENT ─────────────────────────────────

  group('HelocEngine.interestOnlyPayment — rate is PERCENT (8.0, NOT 0.08)', () {
    test('HELOC-G4: \$100k draw @ 8.0% → \$666.67/mo', () {
      approx(HelocEngine.interestOnlyPayment(100000, 8.0), 666.67, tol: 0.01);
    });

    test('HELOC-G5: \$50k draw @ 6.5% → \$270.83/mo', () {
      approx(HelocEngine.interestOnlyPayment(50000, 6.5), 270.83, tol: 0.01);
    });

    test('HELOC-G6: 0% draw rate → \$0 interest', () {
      approx(HelocEngine.interestOnlyPayment(100000, 0.0), 0.0, tol: 0.001);
    });
  });

  // ── wrong-unit smoke test ────────────────────────────────────────────────

  group('Wrong-unit detection: passing 0.08 instead of 8.0', () {
    test('HELOC-W1: decimal rate → \$6.67/mo instead of \$666.67 (100× error)', () {
      // 100000 × 0.08/100/12 = $6.67 — 100× too small, completely wrong
      final wrong = HelocEngine.interestOnlyPayment(100000, 0.08);
      expect(wrong, isNot(closeTo(666.67, 10))); // not the right answer
      expect(wrong, lessThan(10));                 // result is ~$6.67 (near zero vs correct)
    });
  });

  // ── amortizedPayment ─────────────────────────────────────────────────────

  group('HelocEngine.amortizedPayment — rate is PERCENT', () {
    test('HELOC-G7: \$100k @ 8.0% / 20yr ≈ \$836/mo', () {
      approx(HelocEngine.amortizedPayment(100000, 8.0, 20), 836, tol: 1);
    });

    test('HELOC-G8: \$75k @ 7.0% / 10yr ≈ \$872/mo', () {
      approx(HelocEngine.amortizedPayment(75000, 7.0, 10), 872, tol: 2);
    });

    test('HELOC-G9: amortized > interest-only at same rate', () {
      expect(HelocEngine.amortizedPayment(100000, 8.0, 20),
          greaterThan(HelocEngine.interestOnlyPayment(100000, 8.0)));
    });
  });

  // ── ltv ──────────────────────────────────────────────────────────────────

  group('HelocEngine.ltv', () {
    test('HELOC-G10: \$200k / \$400k home → 50%', () {
      approx(HelocEngine.ltv(200000, 400000), 50.0, tol: 0.01);
    });

    test('HELOC-G11: zero home value → 0 (no division by zero)', () {
      expect(HelocEngine.ltv(100000, 0), 0.0);
    });
  });
}
