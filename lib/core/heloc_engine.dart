import 'dart:math' show pow;

class HelocCompareResult {
  final double withdrawalAmount;
  // HELOC
  final double helocDrawPayment;
  final double helocRepayPayment;
  final double helocTotalInterest;
  final double helocInterestOver10Yrs;
  // Cash-out Refi (on equity portion only)
  final double refiMonthlyPayment;
  final double refiTotalInterest;
  final double refiInterestOver10Yrs;
  final double refiClosingCosts;
  final int refiBreakEvenMonths;
  // Verdict
  final bool helocCheaperShortTerm;
  final bool helocCheaperLongTerm;

  const HelocCompareResult({
    required this.withdrawalAmount,
    required this.helocDrawPayment,
    required this.helocRepayPayment,
    required this.helocTotalInterest,
    required this.helocInterestOver10Yrs,
    required this.refiMonthlyPayment,
    required this.refiTotalInterest,
    required this.refiInterestOver10Yrs,
    required this.refiClosingCosts,
    required this.refiBreakEvenMonths,
    required this.helocCheaperShortTerm,
    required this.helocCheaperLongTerm,
  });
}

class HelocEngine {
  // Available equity — uses 85% LTV (industry standard for HELOC/HEL)
  static double availableEquity(double homeValue, double mortgageBalance) {
    final maxLoan = homeValue * 0.85;
    return (maxLoan - mortgageBalance).clamp(0, double.infinity);
  }

  /// Maximum borrowing capacity at a custom LTV (default 85%).
  /// Useful for showing the user their ceiling at various LTV thresholds.
  static double maxBorrowCapacity(double homeValue, double mortgageBalance,
      {double ltvLimit = 0.85}) {
    final maxLoan = homeValue * ltvLimit;
    return (maxLoan - mortgageBalance).clamp(0, double.infinity);
  }

  /// Estimated annual tax savings assuming HELOC interest is fully deductible
  /// (only valid for home-improvement use; user should verify with a tax advisor).
  static double estimatedAnnualTaxSavings(
      double drawAmount, double annualRate, double marginalTaxRate) {
    final annualInterest = drawAmount * (annualRate / 100);
    return annualInterest * (marginalTaxRate / 100);
  }

  // LTV ratio
  static double ltv(double mortgageBalance, double homeValue) =>
      homeValue > 0 ? mortgageBalance / homeValue * 100 : 0;

  // Interest-only payment during draw period
  static double interestOnlyPayment(double drawAmount, double annualRate) =>
      drawAmount * (annualRate / 100 / 12);

  // Amortized payment after draw period
  static double amortizedPayment(double balance, double annualRate, int repaymentYears) {
    if (annualRate == 0) return balance / (repaymentYears * 12);
    final r = annualRate / 100 / 12;
    final n = repaymentYears * 12;
    return balance * r * pow(1 + r, n) / (pow(1 + r, n) - 1);
  }

  // Draw schedule: interest-only phase then amortization
  static List<Map<String, double>> drawSchedule({
    required double drawAmount,
    required double annualRate,
    required int drawYears,    // typically 10
    required int repayYears,   // typically 20
  }) {
    final rows = <Map<String, double>>[];
    final r = annualRate / 100 / 12;
    // Draw period
    for (int m = 1; m <= drawYears * 12; m++) {
      rows.add({'month': m.toDouble(), 'payment': drawAmount * r, 'balance': drawAmount, 'type': 0});
    }
    // Repayment period
    double balance = drawAmount;
    final repayPayment = amortizedPayment(drawAmount, annualRate, repayYears);
    for (int m = 1; m <= repayYears * 12 && balance > 0.01; m++) {
      final interest = balance * r;
      final principal = repayPayment - interest;
      balance -= principal;
      rows.add({'month': (drawYears * 12 + m).toDouble(), 'payment': repayPayment, 'balance': balance.clamp(0, double.infinity), 'type': 1});
    }
    return rows;
  }

  /// Compare HELOC vs Cash-out Refinance for accessing the same equity amount.
  /// Both sides model only the cost of borrowing [withdrawalAmount] —
  /// the existing mortgage payments are excluded for a fair apples-to-apples view.
  static HelocCompareResult compare({
    required double withdrawalAmount,
    required double helocRate,
    required int helocDrawYears,
    required int helocRepayYears,
    required double refiRate,
    required int refiTermYears,
    required double refiClosingCosts,
  }) {
    // ── HELOC side ──────────────────────────────────────────────────────────
    final helocDrawPayment = interestOnlyPayment(withdrawalAmount, helocRate);
    final helocRepayPayment = amortizedPayment(withdrawalAmount, helocRate, helocRepayYears);
    final helocTotalInterest = totalInterestPaid(withdrawalAmount, helocRate, helocDrawYears, helocRepayYears);

    // HELOC interest over 10-year horizon
    final hr = helocRate / 100 / 12;
    final drawMonths = helocDrawYears * 12;
    double helocInterest10 = 0;
    double helocBal = withdrawalAmount;
    for (int m = 1; m <= 120; m++) {
      if (m <= drawMonths) {
        helocInterest10 += helocBal * hr; // interest-only phase
      } else {
        final interest = helocBal * hr;
        helocInterest10 += interest;
        helocBal = (helocBal - (helocRepayPayment - interest)).clamp(0, double.infinity);
      }
    }

    // ── Cash-out Refi side (equity portion only) ─────────────────────────
    final refiPayment = amortizedPayment(withdrawalAmount, refiRate, refiTermYears);
    final refiTotalInterest = refiPayment * refiTermYears * 12 - withdrawalAmount;

    final rr = refiRate / 100 / 12;
    double refiInterest10 = refiClosingCosts; // closing costs upfront
    double refiBal = withdrawalAmount;
    for (int m = 0; m < 120; m++) {
      final interest = refiBal * rr;
      refiInterest10 += interest;
      refiBal = (refiBal - (refiPayment - interest)).clamp(0, double.infinity);
    }

    // Break-even: months for refi to recover closing costs vs HELOC repay payment
    final savingsVsRepay = helocRepayPayment - refiPayment;
    final breakEven = savingsVsRepay > 0
        ? (refiClosingCosts / savingsVsRepay).ceil()
        : 9999;

    return HelocCompareResult(
      withdrawalAmount: withdrawalAmount,
      helocDrawPayment: helocDrawPayment,
      helocRepayPayment: helocRepayPayment,
      helocTotalInterest: helocTotalInterest,
      helocInterestOver10Yrs: helocInterest10,
      refiMonthlyPayment: refiPayment,
      refiTotalInterest: refiTotalInterest + refiClosingCosts,
      refiInterestOver10Yrs: refiInterest10,
      refiClosingCosts: refiClosingCosts,
      refiBreakEvenMonths: breakEven,
      helocCheaperShortTerm: helocInterest10 < refiInterest10,
      helocCheaperLongTerm: helocTotalInterest < (refiTotalInterest + refiClosingCosts),
    );
  }

  static double totalInterestPaid(double drawAmount, double annualRate, int drawYears, int repayYears) {
    final r = annualRate / 100 / 12;
    // Interest during draw period
    double interest = drawAmount * r * drawYears * 12;
    // Interest during repayment period
    final repayPayment = amortizedPayment(drawAmount, annualRate, repayYears);
    double balance = drawAmount;
    for (int m = 0; m < repayYears * 12 && balance > 0.01; m++) {
      final monthInterest = balance * r;
      interest += monthInterest;
      balance -= (repayPayment - monthInterest);
      if (balance < 0) balance = 0;
    }
    return interest;
  }
}
