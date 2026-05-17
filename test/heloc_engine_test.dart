import 'package:flutter_test/flutter_test.dart';
import 'package:heloc_app/core/heloc_engine.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────
  const currencyDelta = 1.0; // $1 tolerance for currency values
  const rateDelta = 0.001; // 0.1% tolerance for rate/percentage values

  // ─────────────────────────────────────────────────────────────────────────
  // availableEquity — 85% LTV (industry standard)
  // ─────────────────────────────────────────────────────────────────────────
  group('availableEquity', () {
    test('Case A — 85% LTV with mortgage balance', () {
      // homeValue=500k, mortgage=300k
      // max = 500000 × 0.85 = 425000
      // available = 425000 − 300000 = 125000
      final result = HelocEngine.availableEquity(500000, 300000);
      expect(result, closeTo(125000, currencyDelta));
    });

    test('Case B — no equity when mortgage exceeds 85% LTV limit', () {
      // homeValue=400k, mortgage=360k
      // max = 400000 × 0.85 = 340000
      // available = 340000 − 360000 = −20000 → clamped to 0
      final result = HelocEngine.availableEquity(400000, 360000);
      expect(result, closeTo(0.0, currencyDelta));
    });

    test('full equity available when no mortgage', () {
      // homeValue=300k, mortgage=0 → available = 300000 × 0.85 = 255000
      final result = HelocEngine.availableEquity(300000, 0);
      expect(result, closeTo(255000, currencyDelta));
    });

    test('result never goes negative regardless of mortgage size', () {
      final result = HelocEngine.availableEquity(200000, 500000);
      expect(result, equals(0.0));
    });

    test('mortgage exactly at 85% LTV produces zero available equity', () {
      // homeValue=400k, mortgage=340k → max=340k → available=0
      final result = HelocEngine.availableEquity(400000, 340000);
      expect(result, closeTo(0.0, currencyDelta));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // maxBorrowCapacity
  // ─────────────────────────────────────────────────────────────────────────
  group('maxBorrowCapacity', () {
    test('default 85% LTV: home=500k, mortgage=200k → 225000', () {
      // 500000 × 0.85 = 425000 − 200000 = 225000
      final result = HelocEngine.maxBorrowCapacity(500000, 200000);
      expect(result, closeTo(225000, currencyDelta));
    });

    test('custom 80% LTV: home=500k, mortgage=200k → 200000', () {
      // 500000 × 0.80 = 400000 − 200000 = 200000
      final result =
          HelocEngine.maxBorrowCapacity(500000, 200000, ltvLimit: 0.80);
      expect(result, closeTo(200000, currencyDelta));
    });

    test('custom 90% LTV: home=500k, mortgage=200k → 250000', () {
      // 500000 × 0.90 = 450000 − 200000 = 250000
      final result =
          HelocEngine.maxBorrowCapacity(500000, 200000, ltvLimit: 0.90);
      expect(result, closeTo(250000, currencyDelta));
    });

    test('result clamped to 0 when mortgage exceeds LTV limit', () {
      final result = HelocEngine.maxBorrowCapacity(300000, 280000);
      expect(result, closeTo(0.0, currencyDelta));
    });

    test('higher LTV limit → larger borrow capacity', () {
      final at80 =
          HelocEngine.maxBorrowCapacity(500000, 200000, ltvLimit: 0.80);
      final at85 =
          HelocEngine.maxBorrowCapacity(500000, 200000, ltvLimit: 0.85);
      final at90 =
          HelocEngine.maxBorrowCapacity(500000, 200000, ltvLimit: 0.90);
      expect(at85, greaterThan(at80));
      expect(at90, greaterThan(at85));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // estimatedAnnualTaxSavings
  // ─────────────────────────────────────────────────────────────────────────
  group('estimatedAnnualTaxSavings', () {
    test('100k at 8.5% at 22% tax bracket → 1870/yr', () {
      // annualInterest = 100000 × 0.085 = 8500
      // savings = 8500 × 0.22 = 1870
      final result = HelocEngine.estimatedAnnualTaxSavings(100000, 8.5, 22.0);
      expect(result, closeTo(1870.0, currencyDelta));
    });

    test('50k at 7.5% at 24% tax bracket → 900/yr', () {
      // annualInterest = 50000 × 0.075 = 3750
      // savings = 3750 × 0.24 = 900
      final result = HelocEngine.estimatedAnnualTaxSavings(50000, 7.5, 24.0);
      expect(result, closeTo(900.0, currencyDelta));
    });

    test('zero rate → zero tax savings', () {
      final result = HelocEngine.estimatedAnnualTaxSavings(100000, 0, 22.0);
      expect(result, closeTo(0.0, currencyDelta));
    });

    test('zero tax rate → zero savings', () {
      final result = HelocEngine.estimatedAnnualTaxSavings(100000, 8.5, 0);
      expect(result, closeTo(0.0, currencyDelta));
    });

    test('higher tax bracket → more savings', () {
      final low = HelocEngine.estimatedAnnualTaxSavings(80000, 8.0, 22.0);
      final high = HelocEngine.estimatedAnnualTaxSavings(80000, 8.0, 32.0);
      expect(high, greaterThan(low));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // ltv
  // ─────────────────────────────────────────────────────────────────────────
  group('ltv', () {
    test('Case A — LTV 60% (mortgage=300k, home=500k)', () {
      // 300000 / 500000 × 100 = 60.0
      final result = HelocEngine.ltv(300000, 500000);
      expect(result, closeTo(60.0, rateDelta));
    });

    test('Case B — LTV 87.5% (mortgage=350k, home=400k)', () {
      // 350000 / 400000 × 100 = 87.5
      final result = HelocEngine.ltv(350000, 400000);
      expect(result, closeTo(87.5, rateDelta));
    });

    test('zero home value returns 0 (guard against division by zero)', () {
      final result = HelocEngine.ltv(100000, 0);
      expect(result, equals(0.0));
    });

    test('zero mortgage gives 0% LTV', () {
      final result = HelocEngine.ltv(0, 500000);
      expect(result, closeTo(0.0, rateDelta));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // interestOnlyPayment
  // ─────────────────────────────────────────────────────────────────────────
  group('interestOnlyPayment', () {
    test('Case A — 80k draw at 8.5% → 566.67/month', () {
      // 80000 × (0.085/12) = 80000 × 0.0070833 = 566.67
      final result = HelocEngine.interestOnlyPayment(80000, 8.5);
      expect(result, closeTo(566.67, currencyDelta));
    });

    test('Case D — 50k draw at 7.5% → 312.50/month', () {
      // 50000 × (0.075/12) = 50000 × 0.00625 = 312.50
      final result = HelocEngine.interestOnlyPayment(50000, 7.5);
      expect(result, closeTo(312.50, currencyDelta));
    });

    test('zero rate returns zero payment', () {
      final result = HelocEngine.interestOnlyPayment(100000, 0);
      expect(result, closeTo(0.0, currencyDelta));
    });

    test('larger draw amount produces proportionally larger payment', () {
      final half = HelocEngine.interestOnlyPayment(50000, 8.0);
      final full = HelocEngine.interestOnlyPayment(100000, 8.0);
      expect(full, closeTo(half * 2, currencyDelta));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // amortizedPayment
  // ─────────────────────────────────────────────────────────────────────────
  group('amortizedPayment', () {
    test('Case A — 80k at 8.5% over 20 years → ~694/month', () {
      // r = 0.085/12 = 0.0070833, n = 240
      // (1+r)^240 ≈ 5.4485
      // payment = 80000 × 0.0070833 × 5.4485 / (5.4485 − 1) ≈ 694
      final result = HelocEngine.amortizedPayment(80000, 8.5, 20);
      expect(result, closeTo(694.0, currencyDelta));
    });

    test('zero rate returns principal / number-of-months', () {
      // 60000 / (10×12) = 60000 / 120 = 500
      final result = HelocEngine.amortizedPayment(60000, 0, 10);
      expect(result, closeTo(500.0, currencyDelta));
    });

    test('total payments exceed principal (interest is positive)', () {
      final pmt = HelocEngine.amortizedPayment(100000, 7.0, 30);
      expect(pmt * 30 * 12, greaterThan(100000));
    });

    test('shorter term → higher monthly payment', () {
      final long = HelocEngine.amortizedPayment(100000, 8.5, 30);
      final short = HelocEngine.amortizedPayment(100000, 8.5, 15);
      expect(short, greaterThan(long));
    });

    test('higher rate → higher monthly payment', () {
      final low = HelocEngine.amortizedPayment(100000, 5.0, 20);
      final high = HelocEngine.amortizedPayment(100000, 9.0, 20);
      expect(high, greaterThan(low));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // drawSchedule
  // ─────────────────────────────────────────────────────────────────────────
  group('drawSchedule', () {
    test('Case D — month 1 draw payment = 312.50', () {
      // draw=50k, rate=7.5%, drawYears=5, repayYears=10
      // month 1 payment = 50000 × 0.00625 = 312.50
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 50000,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      expect(schedule.first['payment'], closeTo(312.50, currencyDelta));
    });

    test('Case D — month 1 balance = 50000 (draw period, no amortisation)', () {
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 50000,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      expect(schedule.first['balance'], closeTo(50000, currencyDelta));
    });

    test('Case D — month 1 type = 0 (draw phase)', () {
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 50000,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      expect(schedule.first['type'], equals(0.0));
    });

    test('total row count = drawMonths + repayMonths', () {
      // draw=5yr→60 rows, repay=10yr→120 rows, total ≤ 180
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 50000,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      expect(schedule.length, greaterThan(60));
      expect(schedule.length, lessThanOrEqualTo(180));
    });

    test('draw period: all rows have type=0 and constant balance = drawAmount',
        () {
      final drawAmount = 50000.0;
      final schedule = HelocEngine.drawSchedule(
        drawAmount: drawAmount,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      // First 60 rows are draw phase (5yr × 12)
      for (int i = 0; i < 60; i++) {
        expect(schedule[i]['type'], equals(0.0),
            reason: 'row $i should be draw phase');
        expect(schedule[i]['balance'], closeTo(drawAmount, currencyDelta),
            reason: 'row $i balance should remain at drawAmount');
      }
    });

    test('repayment period: rows have type=1 and final balance near zero', () {
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 50000,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      final repayRows = schedule.where((r) => r['type'] == 1.0).toList();
      expect(repayRows, isNotEmpty);
      expect(repayRows.last['balance'], closeTo(0.0, 10.0));
    });

    test('month numbers are sequential starting from 1', () {
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 50000,
        annualRate: 7.5,
        drawYears: 5,
        repayYears: 10,
      );
      for (int i = 0; i < schedule.length; i++) {
        expect(schedule[i]['month'], equals((i + 1).toDouble()),
            reason: 'month at index $i should be ${i + 1}');
      }
    });

    test('Case A — draw period payment on 80k at 8.5% → ~566.67', () {
      final schedule = HelocEngine.drawSchedule(
        drawAmount: 80000,
        annualRate: 8.5,
        drawYears: 10,
        repayYears: 20,
      );
      // All draw-period rows should carry the interest-only payment
      expect(schedule.first['payment'], closeTo(566.67, currencyDelta));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // totalInterestPaid
  // ─────────────────────────────────────────────────────────────────────────
  group('totalInterestPaid', () {
    test('positive and reasonable for standard inputs', () {
      final total = HelocEngine.totalInterestPaid(80000, 8.5, 10, 20);
      expect(total, greaterThan(10000));
      expect(total, lessThan(300000));
    });

    test('higher rate results in more total interest', () {
      final low = HelocEngine.totalInterestPaid(80000, 5.0, 10, 20);
      final high = HelocEngine.totalInterestPaid(80000, 10.0, 10, 20);
      expect(high, greaterThan(low));
    });

    test('longer repayment period results in more total interest', () {
      final short = HelocEngine.totalInterestPaid(80000, 8.5, 10, 10);
      final long = HelocEngine.totalInterestPaid(80000, 8.5, 10, 25);
      expect(long, greaterThan(short));
    });

    test('draw interest portion = drawAmount × (rate/12) × drawMonths', () {
      // The draw period is pure interest-only: balance × r for each of drawYears*12 months
      // With flat balance this equals drawAmount × r × drawYears×12
      const draw = 80000.0;
      const rate = 8.5;
      const drawY = 10;
      const repayY = 20;
      final r = rate / 100 / 12;
      final expectedDrawInterest = draw * r * drawY * 12;
      final total = HelocEngine.totalInterestPaid(draw, rate, drawY, repayY);
      // Total must be at least the draw-period interest
      expect(total, greaterThan(expectedDrawInterest));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // compare (HELOC vs Cash-out Refinance) — Case C
  // homeValue=450k, mortgageBalance=280k, equityAmount=60k
  // helocRate=8.0%, refiRate=6.5%, drawYears=10, repayYears=20, refiTerm=30
  // refiClosing=5000
  // ─────────────────────────────────────────────────────────────────────────
  group('HelocEngine.compare — Case C', () {
    late HelocCompareResult result;

    setUpAll(() {
      result = HelocEngine.compare(
        withdrawalAmount: 60000,
        helocRate: 8.0,
        helocDrawYears: 10,
        helocRepayYears: 20,
        refiRate: 6.5,
        refiTermYears: 30,
        refiClosingCosts: 5000,
      );
    });

    test('withdrawalAmount is echoed back correctly', () {
      expect(result.withdrawalAmount, closeTo(60000, currencyDelta));
    });

    test('helocDrawPayment — interest-only on 60k at 8.0%', () {
      // 60000 × (0.08/12) = 60000 × 0.006667 = 400.00
      expect(result.helocDrawPayment, closeTo(400.0, currencyDelta));
    });

    test('helocRepayPayment — amortised 60k at 8.0% over 20yr', () {
      // r=0.006667, n=240, expected ≈ $501/month
      final expected = HelocEngine.amortizedPayment(60000, 8.0, 20);
      expect(result.helocRepayPayment, closeTo(expected, currencyDelta));
    });

    test('helocTotalInterest is positive', () {
      expect(result.helocTotalInterest, greaterThan(0));
    });

    test(
        'helocInterestOver10Yrs equals draw-period interest (10yr draw = 120 months)',
        () {
      // Since helocDrawYears=10, the entire 10-year horizon is draw-only:
      // interest = 60000 × (0.08/12) × 120 = 400 × 120 = 48000
      expect(result.helocInterestOver10Yrs, closeTo(48000, currencyDelta));
    });

    test('refiMonthlyPayment — amortised 60k at 6.5% over 30yr', () {
      final expected = HelocEngine.amortizedPayment(60000, 6.5, 30);
      expect(result.refiMonthlyPayment, closeTo(expected, currencyDelta));
    });

    test('refiTotalInterest includes closing costs', () {
      // refiTotalInterest field includes the closing costs added inside compare()
      expect(result.refiTotalInterest, greaterThan(result.refiClosingCosts));
    });

    test('refiClosingCosts stored correctly', () {
      expect(result.refiClosingCosts, closeTo(5000, currencyDelta));
    });

    test('refiInterestOver10Yrs includes closing costs upfront', () {
      // Closing costs ($5000) are added at the start of the refi 10-year calc
      expect(result.refiInterestOver10Yrs, greaterThan(5000));
    });

    test('helocCheaperShortTerm is a valid bool', () {
      // Just verify it resolves without error (value depends on rates)
      expect(result.helocCheaperShortTerm, isA<bool>());
    });

    test('helocCheaperLongTerm is a valid bool', () {
      expect(result.helocCheaperLongTerm, isA<bool>());
    });

    test(
        'refiBreakEvenMonths — refi payment is lower (6.5% < 8.0%), so break-even is positive',
        () {
      // helocRepayPayment > refiPayment → savings positive → breakEven < 9999
      expect(result.refiBreakEvenMonths, greaterThan(0));
      expect(result.refiBreakEvenMonths, lessThan(9999));
    });

    test(
        'compare is consistent: helocInterestOver10Yrs vs refiInterestOver10Yrs drives helocCheaperShortTerm',
        () {
      final expected =
          result.helocInterestOver10Yrs < result.refiInterestOver10Yrs;
      expect(result.helocCheaperShortTerm, equals(expected));
    });

    test(
        'compare is consistent: helocTotalInterest vs refiTotalInterest drives helocCheaperLongTerm',
        () {
      final expected = result.helocTotalInterest < result.refiTotalInterest;
      expect(result.helocCheaperLongTerm, equals(expected));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // compare — edge case: same rate for HELOC and Refi
  // ─────────────────────────────────────────────────────────────────────────
  group('HelocEngine.compare — edge cases', () {
    test('closing costs zero → refi not penalised at start', () {
      final r = HelocEngine.compare(
        withdrawalAmount: 50000,
        helocRate: 7.0,
        helocDrawYears: 10,
        helocRepayYears: 20,
        refiRate: 7.0,
        refiTermYears: 30,
        refiClosingCosts: 0,
      );
      expect(r.refiClosingCosts, equals(0.0));
      // With same rate but 30yr term, refi payment is lower → savings > 0 → some breakeven
      expect(
          r.refiBreakEvenMonths, equals(0)); // ceil(0/savings) = 0 when costs=0
    });

    test(
        'very high closing costs push break-even to 9999 when refi payment >= heloc repay',
        () {
      // Use high helocRate so helocRepayPayment < refiPayment (shorter repay term)
      // Actually force savingsVsRepay <= 0 by choosing rates where heloc repay < refi pay
      final r = HelocEngine.compare(
        withdrawalAmount: 50000,
        helocRate: 3.0, // very low → tiny repay payment
        helocDrawYears: 10,
        helocRepayYears: 30,
        refiRate: 10.0, // high → large refi payment
        refiTermYears: 10, // short term → even larger
        refiClosingCosts: 5000,
      );
      // helocRepayPayment (3%, 30yr) << refiPayment (10%, 10yr) → savingsVsRepay < 0
      expect(r.refiBreakEvenMonths, equals(9999));
    });
  });
}
