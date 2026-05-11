import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;
export 'package:calcwise_core/calcwise_core.dart' show Insight, InsightSeverity;

// ── Engine ────────────────────────────────────────────────────────────────────

class InsightEngine {
  InsightEngine._();

  /// Returns up to [maxCount] HELOC insights (alerts first).
  static List<Insight> generate({
    required double homeValue,
    required double mortgageBalance,
    required double helocLimit,
    required double annualRatePct,
    required double drawPayment,
    required double repaymentPayment,
    required double totalInterest,
    bool isEs = false,
    int maxCount = 3,
  }) {
    if (homeValue <= 0) return [];
    final insights = <Insight>[];

    final ltv = mortgageBalance / homeValue * 100;

    // ── 1. LTV health ─────────────────────────────────────────────────────────
    if (ltv > 90) {
      insights.add(Insight(
        severity: InsightSeverity.alert,
        icon:     Icons.warning_amber_rounded,
        title: isEs ? 'LTV muy alto' : 'Very High LTV',
        body: isEs
            ? 'LTV muy alto (${ltv.toStringAsFixed(1)}%) — el prestamista puede limitar o denegar el HELOC.'
            : 'Very high LTV (${ltv.toStringAsFixed(1)}%) — lender may limit or deny HELOC.',
      ));
    } else if (ltv >= 80) {
      insights.add(Insight(
        severity: InsightSeverity.warning,
        icon:     Icons.info_outline,
        title: isEs ? 'LTV elevado' : 'Elevated LTV',
        body: isEs
            ? 'LTV del ${ltv.toStringAsFixed(1)}% — es posible que no califiques para las mejores tasas.'
            : 'LTV ${ltv.toStringAsFixed(1)}% — you may not qualify for best rates.',
      ));
    } else {
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon:     Icons.check_circle_outline,
        title: isEs ? 'LTV saludable' : 'Healthy LTV',
        body: isEs
            ? 'LTV saludable del ${ltv.toStringAsFixed(1)}% — buena posición para un HELOC.'
            : 'Healthy LTV (${ltv.toStringAsFixed(1)}%) — good position for HELOC.',
      ));
    }

    // ── 2. Available credit vs. home equity ───────────────────────────────────
    final availableEquity = homeValue * 0.85 - mortgageBalance;
    if (availableEquity > 0 && helocLimit > 0) {
      final pct = (helocLimit / availableEquity * 100).round();
      insights.add(Insight(
        severity: InsightSeverity.good,
        icon:     Icons.account_balance_wallet_outlined,
        title: isEs ? 'Límite HELOC vs. capital' : 'HELOC Limit vs. Equity',
        body: isEs
            ? 'Tu límite HELOC de ${_fmt(helocLimit)} = $pct% del capital disponible.'
            : 'Your HELOC limit of ${_fmt(helocLimit)} = $pct% of available equity.',
      ));
    }

    // ── 3. Rate sensitivity ───────────────────────────────────────────────────
    if (helocLimit > 0 && annualRatePct > 0) {
      final rateMonthly     = annualRatePct / 100 / 12;
      final newRateMonthly  = (annualRatePct + 0.5) / 100 / 12;
      final currentPayment  = helocLimit * rateMonthly;
      final higherPayment   = helocLimit * newRateMonthly;
      final delta           = (higherPayment - currentPayment).abs();
      if (delta >= 5) {
        insights.add(Insight(
          severity: InsightSeverity.warning,
          icon:     Icons.trending_up_outlined,
          title: isEs ? 'Sensibilidad a la tasa' : 'Rate Sensitivity',
          body: isEs
              ? 'Cada aumento de 0.5% en la tasa añade ~${_fmt(delta)}/mes durante el período de disposición.'
              : 'Each 0.5% rate increase adds ~${_fmt(delta)}/month during the draw period.',
        ));
      }
    }

    // ── 4. Repayment shock ────────────────────────────────────────────────────
    if (drawPayment > 0 && repaymentPayment > 0) {
      final ratio = repaymentPayment / drawPayment;
      if (ratio > 1.5) {
        insights.add(Insight(
          severity: InsightSeverity.alert,
          icon:     Icons.arrow_upward_rounded,
          title: isEs ? 'Choque de amortización' : 'Repayment Shock',
          body: isEs
              ? 'El pago de amortización (${_fmt(repaymentPayment)}) es ${ratio.toStringAsFixed(1)}× mayor que el pago durante la disposición (${_fmt(drawPayment)}) — planifica con anticipación.'
              : 'Repayment phase payment (${_fmt(repaymentPayment)}) is ${ratio.toStringAsFixed(1)}× higher than draw phase (${_fmt(drawPayment)}) — plan ahead.',
        ));
      }
    }

    // ── 5. Total interest cost ────────────────────────────────────────────────
    if (totalInterest > 0 && helocLimit > 0) {
      final interestRatio = totalInterest / helocLimit;
      final severity = interestRatio > 0.30
          ? InsightSeverity.alert
          : InsightSeverity.good;
      insights.add(Insight(
        severity: severity,
        icon:     Icons.payments_outlined,
        title: isEs ? 'Costo total de interés' : 'Total Interest Cost',
        body: isEs
            ? 'Interés total estimado durante el plazo: ${_fmt(totalInterest)}.'
            : 'Total estimated interest over term: ${_fmt(totalInterest)}.',
      ));
    }

    // Prioritise alerts > warnings > good, cap at maxCount
    final alerts   = insights.where((i) => i.severity == InsightSeverity.alert).toList();
    final warnings = insights.where((i) => i.severity == InsightSeverity.warning).toList();
    final goods    = insights.where((i) => i.severity == InsightSeverity.good).toList();
    final ordered  = [...alerts, ...warnings, ...goods];
    if (ordered.isEmpty) {
      ordered.add(Insight(
        severity: InsightSeverity.good,
        title: isEs ? 'Cálculo Completado' : 'Calculation Complete',
        body: isEs
            ? 'Desplázate hacia abajo para ver el desglose completo.'
            : 'Scroll down to see the full breakdown.',
      ));
    }
    return ordered.take(maxCount).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  static String _fmt(double amount) {
    final abs = amount.abs();
    String str;
    if (abs >= 1000000) {
      str = '\$${(abs / 1000000).toStringAsFixed(2)}M';
    } else if (abs >= 1000) {
      str = '\$${(abs / 1000).toStringAsFixed(1)}K';
    } else {
      str = '\$${abs.toStringAsFixed(0)}';
    }
    return amount < 0 ? '-$str' : str;
  }
}
