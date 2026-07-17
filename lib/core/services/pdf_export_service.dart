import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../widgets/paywall_hard.dart';
import '../../main.dart' show isSpanishNotifier;
import '../freemium/freemium_service.dart';
import 'package:calcwise_core/calcwise_core.dart';

const _teal = PdfColor(0.0314, 0.4863, 0.4980); // HELOC teal (#087C7F)
const _navy = PdfColor(0.059, 0.200, 0.350);
const _light = PdfColor(0.910, 0.965, 0.980);

// ── Params classes (only sendable types) ────────────────────────────────────

class _HelocPdfParams {
  final double homeValue;
  final double mortgageBalance;
  final double homeEquity;
  final double creditLine;
  final double rate;
  final double drawPhaseMonths;
  final double repaymentMonths;
  final double interestOnlyPayment;
  final double repaymentPayment;
  final double totalInterest;
  final double taxBracket;
  final bool isEs;
  final int nowMs;
  const _HelocPdfParams({
    required this.homeValue,
    required this.mortgageBalance,
    required this.homeEquity,
    required this.creditLine,
    required this.rate,
    required this.drawPhaseMonths,
    required this.repaymentMonths,
    required this.interestOnlyPayment,
    required this.repaymentPayment,
    required this.totalInterest,
    required this.taxBracket,
    required this.isEs,
    required this.nowMs,
  });
}

class _ComparePdfParams {
  final double drawAmount;
  final double helocRate;
  final int helocDrawYears;
  final int helocRepayYears;
  final double refiRate;
  final int refiTermYears;
  final double closingCosts;
  final double loanRate;
  final int loanTermYears;
  final double helocDrawPayment;
  final double helocRepayPayment;
  final double helocTotalInterest;
  final double refiMonthlyPayment;
  final double refiTotalInterest;
  final double loanMonthlyPayment;
  final double loanTotalInterest;
  final String bestOption;
  final bool isEs;
  final bool isFr;
  final int nowMs;
  const _ComparePdfParams({
    required this.drawAmount,
    required this.helocRate,
    required this.helocDrawYears,
    required this.helocRepayYears,
    required this.refiRate,
    required this.refiTermYears,
    required this.closingCosts,
    required this.loanRate,
    required this.loanTermYears,
    required this.helocDrawPayment,
    required this.helocRepayPayment,
    required this.helocTotalInterest,
    required this.refiMonthlyPayment,
    required this.refiTotalInterest,
    required this.loanMonthlyPayment,
    required this.loanTotalInterest,
    required this.bestOption,
    required this.isEs,
    required this.isFr,
    required this.nowMs,
  });
}

class _DrawOptimizerPdfParams {
  final double creditLimit;
  final double rate;
  final int drawYears;
  final int repayYears;
  final double totalDraw;
  final String optimalStrategy;
  final double yourPlanInterest;
  final double allAtOnceInterest;
  final double spreadEvenlyInterest;
  final double optimalTotalInterest;
  final double optimalDrawInterest;
  final double optimalBalanceAtDrawEnd;
  final int optimalPayoffMonths;
  final bool isEs;
  final bool isFr;
  final int nowMs;
  const _DrawOptimizerPdfParams({
    required this.creditLimit,
    required this.rate,
    required this.drawYears,
    required this.repayYears,
    required this.totalDraw,
    required this.optimalStrategy,
    required this.yourPlanInterest,
    required this.allAtOnceInterest,
    required this.spreadEvenlyInterest,
    required this.optimalTotalInterest,
    required this.optimalDrawInterest,
    required this.optimalBalanceAtDrawEnd,
    required this.optimalPayoffMonths,
    required this.isEs,
    required this.isFr,
    required this.nowMs,
  });
}

class _HelocVsCashoutPdfParams {
  final double homeValue;
  final double existingBalance;
  final double existingRate;
  final int existingYears;
  final double cashNeeded;
  final double helocRate;
  final double refiRate;
  final double closingPct;
  final bool financeClosing;
  final double helocIOPayment;
  final double helocPIPayment;
  final double helocTotalMonthly;
  final double helocTotalInterest30y;
  final double refiNewBalance;
  final double refiMonthly;
  final double refiClosingCosts;
  final double refiTotalInterest30y;
  final double refiTotalCost;
  final int breakevenMonths;
  final int winnerIndex;
  final bool isEs;
  final bool isFr;
  final int nowMs;
  const _HelocVsCashoutPdfParams({
    required this.homeValue,
    required this.existingBalance,
    required this.existingRate,
    required this.existingYears,
    required this.cashNeeded,
    required this.helocRate,
    required this.refiRate,
    required this.closingPct,
    required this.financeClosing,
    required this.helocIOPayment,
    required this.helocPIPayment,
    required this.helocTotalMonthly,
    required this.helocTotalInterest30y,
    required this.refiNewBalance,
    required this.refiMonthly,
    required this.refiClosingCosts,
    required this.refiTotalInterest30y,
    required this.refiTotalCost,
    required this.breakevenMonths,
    required this.winnerIndex,
    required this.isEs,
    required this.isFr,
    required this.nowMs,
  });
}

class _PaymentShockPdfParams {
  final double helocBalance;
  final double currentRate;
  final double projectedRate;
  final int repayYears;
  final double ioPayment;
  final double piPayment;
  final double shockPct;
  final double dollarIncrease;
  final double totalInterest;
  final bool isEs;
  final bool isFr;
  final int nowMs;
  const _PaymentShockPdfParams({
    required this.helocBalance,
    required this.currentRate,
    required this.projectedRate,
    required this.repayYears,
    required this.ioPayment,
    required this.piPayment,
    required this.shockPct,
    required this.dollarIncrease,
    required this.totalInterest,
    required this.isEs,
    required this.isFr,
    required this.nowMs,
  });
}

// ── Shared helpers (top-level, usable in isolates) ──────────────────────────

pw.Widget _sectionBox(String title, List<pw.Widget> rows) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: _navy,
            child: pw.Text(title,
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white))),
        pw.Container(
            padding: const pw.EdgeInsets.all(AppSpacing.sm),
            decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5)),
            child: pw.Column(children: rows)),
      ],
    );

pw.Widget _row2(String label, String value,
        {bool bold = false, PdfColor? color}) =>
    pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(label,
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey800)),
            pw.Text(value,
                style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight:
                        bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: color ?? PdfColors.black)),
          ]),
    );

pw.Widget _th(String text) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white)),
    );

pw.TableRow _tr3(String label, String v1, String v2, String v3,
    {bool oddRow = false, bool highlight = false}) {
  final bg = oddRow ? _light : PdfColors.white;
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: bg),
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(label,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight:
                    highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: PdfColors.grey800)),
      ),
      ...[v1, v2, v3].map((v) => pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(v,
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight:
                        highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: highlight ? _teal : PdfColors.black)),
          )),
    ],
  );
}

pw.TableRow _tr2Strategy(String label, String value,
    {required bool isOptimal, bool oddRow = false}) {
  return pw.TableRow(
    decoration: pw.BoxDecoration(color: oddRow ? _light : PdfColors.white),
    children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Row(children: [
          if (isOptimal)
            pw.Container(
              width: 6,
              height: 6,
              decoration: const pw.BoxDecoration(
                  color: _teal, shape: pw.BoxShape.circle),
              margin: const pw.EdgeInsets.only(right: 4),
            ),
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight:
                      isOptimal ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: isOptimal ? _teal : PdfColors.grey800)),
        ]),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(value,
            style: pw.TextStyle(
                fontSize: 8,
                fontWeight:
                    isOptimal ? pw.FontWeight.bold : pw.FontWeight.normal,
                color: isOptimal ? _teal : PdfColors.black)),
      ),
    ],
  );
}

// ── Top-level isolate build functions ───────────────────────────────────────

Future<Uint8List> _buildHelocPdf(_HelocPdfParams p) async {
  await initializeDateFormatting();
  final cur2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final dateF = DateFormat('MMMM d, yyyy', p.isEs ? 'es' : 'en');
  final now = DateTime.fromMillisecondsSinceEpoch(p.nowMs);

  final ltv = p.homeValue > 0 ? (p.mortgageBalance / p.homeValue * 100) : 0.0;
  final drawYears = (p.drawPhaseMonths / 12).ceil().clamp(1, 10);

  final drawScheduleRows = <pw.TableRow>[];
  for (int yr = 1; yr <= drawYears.clamp(1, 5); yr++) {
    final annualInterest = p.creditLine * (p.rate / 100);
    drawScheduleRows.add(pw.TableRow(
      decoration:
          pw.BoxDecoration(color: yr.isOdd ? _light : PdfColors.white),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text('${p.isEs ? "Año" : "Year"} $yr',
              style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(cur2.format(p.interestOnlyPayment),
              style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(cur0.format(annualInterest),
              style: const pw.TextStyle(fontSize: 8)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(cur0.format(p.creditLine),
              style: const pw.TextStyle(fontSize: 8, color: _teal)),
        ),
      ],
    ));
  }

  pw.Widget buildPage(pw.Context ctx) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                        p.isEs
                            ? 'Calculadora HELOC'
                            : 'HELOC Calculator',
                        style: pw.TextStyle(
                            fontSize: AppTextSize.title,
                            fontWeight: pw.FontWeight.bold,
                            color: _teal)),
                    pw.Text(
                        p.isEs
                            ? 'Informe: Línea de Crédito sobre Valor Inmobiliario'
                            : 'Home Equity Line of Credit Report',
                        style: const pw.TextStyle(
                            fontSize: AppTextSize.xs,
                            color: PdfColors.grey700)),
                  ]),
              pw.Text(dateF.format(now),
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
            ]),
        pw.Container(
            height: 2,
            color: _teal,
            margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(p.isEs ? 'VALOR INMOBILIARIO' : 'HOME EQUITY', [
              _row2(p.isEs ? 'Valor de la vivienda' : 'Home Value',
                  cur0.format(p.homeValue)),
              _row2(p.isEs ? 'Saldo hipotecario' : 'Mortgage Balance',
                  cur0.format(p.mortgageBalance)),
              _row2(p.isEs ? 'Capital disponible' : 'Home Equity',
                  cur0.format(p.homeEquity),
                  bold: true, color: _teal),
              _row2(p.isEs ? 'Ratio LTV' : 'LTV Ratio',
                  '${ltv.toStringAsFixed(1)}%'),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox(p.isEs ? 'CONDICIONES DEL HELOC' : 'HELOC TERMS', [
              _row2(p.isEs ? 'Línea de crédito' : 'Credit Line',
                  cur0.format(p.creditLine)),
              _row2(p.isEs ? 'Tasa de interés' : 'Interest Rate',
                  '${p.rate.toStringAsFixed(2)}%'),
              _row2(p.isEs ? 'Período de disposición' : 'Draw Period',
                  '${p.drawPhaseMonths.toStringAsFixed(0)} ${p.isEs ? "meses" : "months"}'),
              _row2(p.isEs ? 'Período de pago' : 'Repayment Period',
                  '${p.repaymentMonths.toStringAsFixed(0)} ${p.isEs ? "meses" : "months"}'),
            ]),
          ])),
          pw.SizedBox(width: 14),
          pw.Expanded(
              child: pw.Column(children: [
            _sectionBox(
                p.isEs ? 'DESGLOSE DE PAGOS' : 'PAYMENT BREAKDOWN', [
              _row2(
                  p.isEs
                      ? 'Pago solo interés (disposición)'
                      : 'Draw Phase Payment',
                  cur2.format(p.interestOnlyPayment)),
              _row2(
                  p.isEs
                      ? 'Pago mensual (amortización)'
                      : 'Monthly Repayment',
                  cur2.format(p.repaymentPayment),
                  bold: true,
                  color: _navy),
              _row2(p.isEs ? 'Interés total' : 'Total Interest',
                  cur0.format(p.totalInterest)),
            ]),
            pw.SizedBox(height: 10),
            _sectionBox(
                p.isEs
                    ? 'CALENDARIO DE DISPOSICIÓN (AÑOS 1-5)'
                    : 'DRAW SCHEDULE (YEARS 1-5)',
                [
                  pw.Table(
                    border: pw.TableBorder.all(
                        color: PdfColors.grey300, width: 0.5),
                    columnWidths: {
                      0: const pw.FixedColumnWidth(36),
                      1: const pw.FlexColumnWidth(),
                      2: const pw.FlexColumnWidth(),
                      3: const pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(
                        decoration:
                            const pw.BoxDecoration(color: _navy),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            child: pw.Text(p.isEs ? 'Año' : 'Year',
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            child: pw.Text(
                                p.isEs ? 'Pago/mes' : 'Payment/mo',
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            child: pw.Text(
                                p.isEs ? 'Interés/año' : 'Interest/yr',
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 6, vertical: 3),
                            child: pw.Text(p.isEs ? 'Saldo' : 'Balance',
                                style: pw.TextStyle(
                                    fontSize: 7,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.white)),
                          ),
                        ],
                      ),
                      ...drawScheduleRows,
                    ],
                  ),
                ]),
          ])),
        ]),
        pw.Spacer(),
        PdfBrandHelper.footer(ctx, 'HELOC Calculator'),
      ]);

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (ctx) => buildPage(ctx),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildComparePdf(_ComparePdfParams p) async {
  await initializeDateFormatting();
  final cur2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final dateF = DateFormat('MMMM d, yyyy', p.isEs ? 'es' : 'en');
  final now = DateTime.fromMillisecondsSinceEpoch(p.nowMs);

  final minTotal = [p.helocTotalInterest, p.refiTotalInterest, p.loanTotalInterest]
      .reduce((a, b) => a < b ? a : b);
  final winnerLabel = p.helocTotalInterest == minTotal
      ? 'HELOC'
      : (p.refiTotalInterest == minTotal
          ? (p.isFr
              ? 'Refi avec retrait'
              : p.isEs
                  ? 'Refinanciación'
                  : 'Cash-Out Refi')
          : (p.isFr
              ? 'Prêt personnel'
              : p.isEs
                  ? 'Préstamo Personal'
                  : 'Personal Loan'));

  pw.Widget buildPage(pw.Context ctx) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  p.isFr
                      ? 'Comparaison de financement'
                      : p.isEs
                          ? 'Comparación de Financiamiento'
                          : 'Financing Comparison',
                  style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal),
                ),
                pw.Text(
                  p.isFr
                      ? 'HELOC vs Refi avec retrait vs Prêt personnel'
                      : p.isEs
                          ? 'HELOC vs Refinanciación vs Préstamo Personal'
                          : 'HELOC vs Cash-Out Refi vs Personal Loan',
                  style: const pw.TextStyle(
                      fontSize: AppTextSize.xs, color: PdfColors.grey700),
                ),
              ]),
          pw.Text(dateF.format(now),
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
      pw.Container(
          height: 2,
          color: _teal,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
      _sectionBox(
          p.isFr ? 'PARAMÈTRES' : p.isEs ? 'PARÁMETROS' : 'INPUTS', [
        _row2(
            p.isFr
                ? 'Montant à financer'
                : p.isEs
                    ? 'Monto a financiar'
                    : 'Amount to Finance',
            cur0.format(p.drawAmount)),
        _row2(
            p.isFr
                ? 'Taux HELOC'
                : p.isEs
                    ? 'Tasa HELOC'
                    : 'HELOC Rate',
            '${p.helocRate.toStringAsFixed(2)}%'),
        _row2(
            p.isFr
                ? 'Période HELOC (disp/remb.)'
                : p.isEs
                    ? 'Período HELOC (disp/pago)'
                    : 'HELOC Period (draw/repay)',
            '${p.helocDrawYears}y / ${p.helocRepayYears}y'),
        _row2(
            p.isFr
                ? 'Taux refi'
                : p.isEs
                    ? 'Tasa Refi'
                    : 'Refi Rate',
            '${p.refiRate.toStringAsFixed(2)}%'),
        _row2(
            p.isFr
                ? 'Durée refi'
                : p.isEs
                    ? 'Plazo Refi'
                    : 'Refi Term',
            '${p.refiTermYears}y'),
        _row2(
            p.isFr
                ? 'Frais de clôture refi'
                : p.isEs
                    ? 'Costos cierre Refi'
                    : 'Refi Closing Costs',
            cur0.format(p.closingCosts)),
        _row2(
            p.isFr
                ? 'Taux prêt personnel'
                : p.isEs
                    ? 'Tasa Préstamo Personal'
                    : 'Personal Loan Rate',
            '${p.loanRate.toStringAsFixed(2)}%'),
        _row2(
            p.isFr
                ? 'Durée prêt personnel'
                : p.isEs
                    ? 'Plazo Préstamo Personal'
                    : 'Personal Loan Term',
            '${p.loanTermYears}y'),
      ]),
      pw.SizedBox(height: 10),
      _sectionBox(
          p.isFr ? 'COMPARAISON' : p.isEs ? 'COMPARACIÓN' : 'COMPARISON', [
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(),
            2: const pw.FlexColumnWidth(),
            3: const pw.FlexColumnWidth(),
          },
          children: [
            pw.TableRow(
              decoration: const pw.BoxDecoration(color: _navy),
              children: [
                _th(''),
                _th('HELOC'),
                _th(p.isFr
                    ? 'Refi'
                    : p.isEs
                        ? 'Refi'
                        : 'Cash-Out Refi'),
                _th(p.isFr
                    ? 'Prêt perso.'
                    : p.isEs
                        ? 'Préstamo'
                        : 'Personal Loan'),
              ],
            ),
            _tr3(
                p.isFr
                    ? 'Paiement mensuel initial'
                    : p.isEs
                        ? 'Pago mensual inicial'
                        : 'Monthly (initial)',
                cur2.format(p.helocDrawPayment),
                cur2.format(p.refiMonthlyPayment),
                cur2.format(p.loanMonthlyPayment),
                oddRow: true),
            _tr3(
                p.isFr
                    ? 'Paiement mensuel (remb.)'
                    : p.isEs
                        ? 'Pago mensual (pago)'
                        : 'Monthly (repayment)',
                cur2.format(p.helocRepayPayment),
                cur2.format(p.refiMonthlyPayment),
                cur2.format(p.loanMonthlyPayment)),
            _tr3(
                p.isFr
                    ? 'Intérêts totaux'
                    : p.isEs
                        ? 'Interés total'
                        : 'Total Interest',
                cur0.format(p.helocTotalInterest),
                cur0.format(p.refiTotalInterest),
                cur0.format(p.loanTotalInterest),
                oddRow: true,
                highlight: true),
          ],
        ),
      ]),
      pw.SizedBox(height: 10),
      _sectionBox(
          p.isFr
              ? 'RECOMMANDATION'
              : p.isEs
                  ? 'RECOMENDACIÓN'
                  : 'RECOMMENDATION', [
        _row2(
            p.isFr
                ? 'Meilleure option (intérêts totaux les plus bas)'
                : p.isEs
                    ? 'Mejor opción (interés total mínimo)'
                    : 'Best option (lowest total interest)',
            winnerLabel,
            bold: true,
            color: _teal),
      ]),
      pw.Spacer(),
      PdfBrandHelper.footer(ctx, 'HELOC Calculator'),
    ],
  );

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (ctx) => buildPage(ctx),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildDrawOptimizerPdf(_DrawOptimizerPdfParams p) async {
  await initializeDateFormatting();
  final cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final dateF = DateFormat('MMMM d, yyyy', p.isEs ? 'es' : 'en');
  final now = DateTime.fromMillisecondsSinceEpoch(p.nowMs);

  String localLabel(String label) {
    if (p.isFr) {
      switch (label) {
        case 'Your Plan':
          return 'Mon plan';
        case 'All at Once':
          return 'Tout d\'un coup';
        case 'Spread Evenly':
          return 'Répartir';
        default:
          return label;
      }
    }
    if (!p.isEs) return label;
    switch (label) {
      case 'Your Plan':
        return 'Tu Plan';
      case 'All at Once':
        return 'Todo a la Vez';
      case 'Spread Evenly':
        return 'Distribuido';
      default:
        return label;
    }
  }

  final spreadSavings = p.allAtOnceInterest - p.spreadEvenlyInterest;

  pw.Widget buildPage(pw.Context ctx) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  p.isFr
                      ? 'Optimiseur de période de tirage HELOC'
                      : p.isEs
                          ? 'Optimizador de Disposición HELOC'
                          : 'HELOC Draw Period Optimizer',
                  style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal),
                ),
                pw.Text(
                  p.isFr
                      ? 'Analyse des stratégies de tirage'
                      : p.isEs
                          ? 'Análisis de estrategias de disposición'
                          : 'Draw strategy analysis',
                  style: const pw.TextStyle(
                      fontSize: AppTextSize.xs, color: PdfColors.grey700),
                ),
              ]),
          pw.Text(dateF.format(now),
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
      pw.Container(
          height: 2,
          color: _teal,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(
              p.isFr ? 'PARAMÈTRES' : p.isEs ? 'PARÁMETROS' : 'INPUTS', [
            _row2(
                p.isFr
                    ? 'Limite de crédit'
                    : p.isEs
                        ? 'Límite de crédito'
                        : 'Credit Limit',
                cur0.format(p.creditLimit)),
            _row2(
                p.isFr
                    ? 'Total à tirer'
                    : p.isEs
                        ? 'Total a disponer'
                        : 'Total Draw',
                cur0.format(p.totalDraw)),
            _row2(
                p.isFr
                    ? 'Taux HELOC'
                    : p.isEs
                        ? 'Tasa HELOC'
                        : 'HELOC Rate',
                '${p.rate.toStringAsFixed(2)}%'),
            _row2(
                p.isFr
                    ? 'Période de tirage'
                    : p.isEs
                        ? 'Período disposición'
                        : 'Draw Period',
                '${p.drawYears}y'),
            _row2(
                p.isFr
                    ? 'Période de remboursement'
                    : p.isEs
                        ? 'Período de pago'
                        : 'Repayment Period',
                '${p.repayYears}y'),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              p.isFr
                  ? 'STRATÉGIE OPTIMALE'
                  : p.isEs
                      ? 'MEJOR ESTRATEGIA'
                      : 'OPTIMAL STRATEGY', [
            _row2(
                p.isFr
                    ? 'Stratégie optimale'
                    : p.isEs
                        ? 'Estrategia óptima'
                        : 'Optimal Strategy',
                localLabel(p.optimalStrategy),
                bold: true,
                color: _teal),
            _row2(
                p.isFr
                    ? 'Intérêts totaux'
                    : p.isEs
                        ? 'Interés total'
                        : 'Total Interest',
                cur0.format(p.optimalTotalInterest),
                bold: true),
            _row2(
                p.isFr
                    ? 'Intérêts phase tirage'
                    : p.isEs
                        ? 'Interés fase disposición'
                        : 'Draw Phase Interest',
                cur0.format(p.optimalDrawInterest)),
            _row2(
                p.isFr
                    ? 'Solde en fin de tirage'
                    : p.isEs
                        ? 'Balance al final de disposición'
                        : 'Balance at Draw End',
                cur0.format(p.optimalBalanceAtDrawEnd)),
            _row2(
                p.isFr
                    ? 'Durée totale'
                    : p.isEs
                        ? 'Plazo total'
                        : 'Payoff Timeline',
                '${(p.optimalPayoffMonths / 12).toStringAsFixed(1)}y'),
          ]),
        ])),
        pw.SizedBox(width: 14),
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(
              p.isFr
                  ? 'COMPARAISON DES STRATÉGIES'
                  : p.isEs
                      ? 'COMPARACIÓN DE ESTRATEGIAS'
                      : 'STRATEGY COMPARISON', [
            pw.Table(
              border:
                  pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _navy),
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: pw.Text(
                          p.isFr
                              ? 'Stratégie'
                              : p.isEs
                                  ? 'Estrategia'
                                  : 'Strategy',
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: pw.Text(
                          p.isFr
                              ? 'Intérêts totaux'
                              : p.isEs
                                  ? 'Interés total'
                                  : 'Total Interest',
                          style: pw.TextStyle(
                              fontSize: 7,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.white)),
                    ),
                  ],
                ),
                _tr2Strategy(localLabel('Your Plan'),
                    cur0.format(p.yourPlanInterest),
                    isOptimal: p.optimalStrategy == 'Your Plan',
                    oddRow: true),
                _tr2Strategy(localLabel('All at Once'),
                    cur0.format(p.allAtOnceInterest),
                    isOptimal: p.optimalStrategy == 'All at Once'),
                _tr2Strategy(localLabel('Spread Evenly'),
                    cur0.format(p.spreadEvenlyInterest),
                    isOptimal: p.optimalStrategy == 'Spread Evenly',
                    oddRow: true),
              ],
            ),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              p.isFr
                  ? 'ÉCONOMIES POTENTIELLES'
                  : p.isEs
                      ? 'AHORRO POTENCIAL'
                      : 'POTENTIAL SAVINGS', [
            _row2(
              p.isFr
                  ? 'Économies (répartir vs tout d\'un coup)'
                  : p.isEs
                      ? 'Ahorro (distribuido vs todo a la vez)'
                      : 'Savings (spread vs all at once)',
              spreadSavings > 0 ? cur0.format(spreadSavings) : '\$0',
              bold: spreadSavings > 0,
              color: spreadSavings > 0 ? _teal : null,
            ),
          ]),
        ])),
      ]),
      pw.Spacer(),
      PdfBrandHelper.footer(ctx, 'HELOC Calculator'),
    ],
  );

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (ctx) => buildPage(ctx),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildHelocVsCashoutPdf(_HelocVsCashoutPdfParams p) async {
  await initializeDateFormatting();
  final cur2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final dateF = DateFormat('MMMM d, yyyy', p.isEs ? 'es' : 'en');
  final now = DateTime.fromMillisecondsSinceEpoch(p.nowMs);

  final winnerLabel = p.winnerIndex == 0
      ? 'HELOC'
      : (p.isFr
          ? 'Refi avec retrait'
          : p.isEs
              ? 'Refi con Retiro'
              : 'Cash-Out Refi');

  pw.Widget buildPage(pw.Context ctx) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  p.isFr
                      ? 'HELOC vs Refi avec retrait'
                      : p.isEs
                          ? 'HELOC vs Refinanciación con Retiro'
                          : 'HELOC vs Cash-Out Refinance',
                  style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal),
                ),
                pw.Text(
                  p.isFr
                      ? 'Comparaison des options d\'accès à la valeur nette'
                      : p.isEs
                          ? 'Comparación de opciones de acceso a capital'
                          : 'Home equity access comparison',
                  style: const pw.TextStyle(
                      fontSize: AppTextSize.xs, color: PdfColors.grey700),
                ),
              ]),
          pw.Text(dateF.format(now),
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
      pw.Container(
          height: 2,
          color: _teal,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(
              p.isFr ? 'PARAMÈTRES' : p.isEs ? 'PARÁMETROS' : 'INPUTS', [
            _row2(
                p.isFr
                    ? 'Valeur de la maison'
                    : p.isEs
                        ? 'Valor vivienda'
                        : 'Home Value',
                cur0.format(p.homeValue)),
            _row2(
                p.isFr
                    ? 'Solde hypothèque existante'
                    : p.isEs
                        ? 'Saldo hipoteca existente'
                        : 'Existing Mortgage Balance',
                cur0.format(p.existingBalance)),
            _row2(
                p.isFr
                    ? 'Taux hypothèque existante'
                    : p.isEs
                        ? 'Tasa hipoteca existente'
                        : 'Existing Mortgage Rate',
                '${p.existingRate.toStringAsFixed(2)}%'),
            _row2(
                p.isFr
                    ? 'Années restantes hypothèque'
                    : p.isEs
                        ? 'Años restantes hipoteca'
                        : 'Existing Mortgage Years Left',
                '${p.existingYears}y'),
            _row2(
                p.isFr
                    ? 'Liquidités nécessaires'
                    : p.isEs
                        ? 'Efectivo necesario'
                        : 'Cash Needed',
                cur0.format(p.cashNeeded)),
            _row2(
                p.isFr
                    ? 'Taux HELOC'
                    : p.isEs
                        ? 'Tasa HELOC'
                        : 'HELOC Rate',
                '${p.helocRate.toStringAsFixed(2)}%'),
            _row2(
                p.isFr
                    ? 'Taux refi'
                    : p.isEs
                        ? 'Tasa Refi'
                        : 'Refi Rate',
                '${p.refiRate.toStringAsFixed(2)}%'),
            _row2(
                p.isFr
                    ? 'Frais de clôture refi (%)'
                    : p.isEs
                        ? 'Costos cierre Refi (%)'
                        : 'Refi Closing Costs (%)',
                '${p.closingPct.toStringAsFixed(1)}%'),
            _row2(
                p.isFr
                    ? 'Financer les frais de clôture'
                    : p.isEs
                        ? 'Financiar costos cierre'
                        : 'Finance Closing Costs',
                p.financeClosing
                    ? (p.isFr ? 'Oui' : p.isEs ? 'Sí' : 'Yes')
                    : 'No'),
          ]),
        ])),
        pw.SizedBox(width: 14),
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox('HELOC', [
            _row2(
                p.isFr
                    ? 'Paiement mensuel initial (int. seul.)'
                    : p.isEs
                        ? 'Pago mensual inicial (solo int.)'
                        : 'Initial Monthly (interest-only)',
                cur2.format(p.helocTotalMonthly)),
            _row2(
                p.isFr
                    ? 'Paiement mensuel (remb.)'
                    : p.isEs
                        ? 'Pago mensual (fase pago)'
                        : 'Monthly (repay phase)',
                cur2.format(p.helocPIPayment)),
            _row2(
                p.isFr
                    ? 'Frais initiaux'
                    : p.isEs
                        ? 'Costos iniciales'
                        : 'Upfront Costs',
                r'$0'),
            _row2(
                p.isFr
                    ? 'Intérêts totaux 30 ans'
                    : p.isEs
                        ? 'Interés total 30 años'
                        : 'Total Interest 30y',
                cur0.format(p.helocTotalInterest30y),
                bold: p.winnerIndex == 0,
                color: p.winnerIndex == 0 ? _teal : null),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              p.isFr
                  ? 'REFI AVEC RETRAIT'
                  : p.isEs
                      ? 'REFI CON RETIRO'
                      : 'CASH-OUT REFI', [
            _row2(
                p.isFr
                    ? 'Nouveau solde hypothèque'
                    : p.isEs
                        ? 'Nuevo saldo hipoteca'
                        : 'New Mortgage Balance',
                cur0.format(p.refiNewBalance)),
            _row2(
                p.isFr
                    ? 'Paiement mensuel'
                    : p.isEs
                        ? 'Pago mensual'
                        : 'Monthly Payment',
                cur2.format(p.refiMonthly)),
            _row2(
                p.isFr
                    ? 'Frais de clôture'
                    : p.isEs
                        ? 'Costos de cierre'
                        : 'Closing Costs',
                p.financeClosing
                    ? (p.isFr
                        ? 'Financés'
                        : p.isEs
                            ? 'Financiados'
                            : 'Financed')
                    : cur0.format(p.refiClosingCosts)),
            _row2(
                p.isFr
                    ? 'Coût total'
                    : p.isEs
                        ? 'Costo total'
                        : 'Total Cost',
                cur0.format(p.refiTotalCost),
                bold: p.winnerIndex == 1,
                color: p.winnerIndex == 1 ? _teal : null),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              p.isFr ? 'RÉSULTAT' : p.isEs ? 'RESULTADO' : 'OUTCOME', [
            _row2(
                p.isFr
                    ? 'Meilleure option'
                    : p.isEs
                        ? 'Mejor opción'
                        : 'Best Option',
                winnerLabel,
                bold: true,
                color: _teal),
            if (p.breakevenMonths < 9999)
              _row2(
                  p.isFr
                      ? 'Seuil de rentabilité'
                      : p.isEs
                          ? 'Punto de equilibrio'
                          : 'Break-Even',
                  '${p.breakevenMonths} ${p.isFr ? "mois" : p.isEs ? "meses" : "months"} (~${(p.breakevenMonths / 12).toStringAsFixed(1)}y)'),
          ]),
        ])),
      ]),
      pw.Spacer(),
      PdfBrandHelper.footer(ctx, 'HELOC Calculator'),
    ],
  );

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (ctx) => buildPage(ctx),
  ));
  return await pdf.save();
}

Future<Uint8List> _buildPaymentShockPdf(_PaymentShockPdfParams p) async {
  await initializeDateFormatting();
  final cur2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final dateF = DateFormat('MMMM d, yyyy', p.isEs ? 'es' : 'en');
  final now = DateTime.fromMillisecondsSinceEpoch(p.nowMs);

  pw.Widget buildPage(pw.Context ctx) => pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  p.isFr
                      ? 'Calculatrice de choc de paiement HELOC'
                      : p.isEs
                          ? 'Calculadora de Choque de Pago HELOC'
                          : 'HELOC Payment Shock Calculator',
                  style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: _teal),
                ),
                pw.Text(
                  p.isFr
                      ? 'Projection du paiement à la fin de la période de tirage'
                      : p.isEs
                          ? 'Proyección del pago al final del período de disposición'
                          : 'Payment projection at end of draw period',
                  style: const pw.TextStyle(
                      fontSize: AppTextSize.xs, color: PdfColors.grey700),
                ),
              ]),
          pw.Text(dateF.format(now),
              style: const pw.TextStyle(
                  fontSize: 9, color: PdfColors.grey600)),
        ],
      ),
      pw.Container(
          height: 2,
          color: _teal,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(
              p.isFr ? 'PARAMÈTRES' : p.isEs ? 'PARÁMETROS' : 'INPUTS', [
            _row2(
                p.isFr
                    ? 'Solde HELOC'
                    : p.isEs
                        ? 'Saldo HELOC'
                        : 'HELOC Balance',
                cur0.format(p.helocBalance)),
            _row2(
                p.isFr
                    ? 'Taux actuel (période de tirage)'
                    : p.isEs
                        ? 'Tasa actual (período disposición)'
                        : 'Current Rate (draw period)',
                '${p.currentRate.toStringAsFixed(2)}%'),
            _row2(
                p.isFr
                    ? 'Taux projeté (période de remb.)'
                    : p.isEs
                        ? 'Tasa proyectada (período pago)'
                        : 'Projected Rate (repayment period)',
                '${p.projectedRate.toStringAsFixed(2)}%'),
            _row2(
                p.isFr
                    ? 'Période de remboursement'
                    : p.isEs
                        ? 'Período de pago'
                        : 'Repayment Period',
                '${p.repayYears}y'),
          ]),
        ])),
        pw.SizedBox(width: 14),
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(
              p.isFr ? 'PAIEMENTS' : p.isEs ? 'PAGOS' : 'PAYMENTS', [
            _row2(
                p.isFr
                    ? 'Paiement actuel (int. seul.)'
                    : p.isEs
                        ? 'Pago actual (solo interés)'
                        : 'Current Payment (interest-only)',
                cur2.format(p.ioPayment)),
            _row2(
                p.isFr
                    ? 'Nouveau paiement (C + I)'
                    : p.isEs
                        ? 'Nuevo pago (P + I)'
                        : 'New Payment (P + I)',
                cur2.format(p.piPayment),
                bold: true,
                color: const PdfColor(0.78, 0.16, 0.16)),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              p.isFr
                  ? 'CHOC DE PAIEMENT'
                  : p.isEs
                      ? 'CHOQUE DE PAGO'
                      : 'PAYMENT SHOCK', [
            _row2(
                p.isFr
                    ? 'Augmentation en pourcentage'
                    : p.isEs
                        ? 'Aumento porcentual'
                        : 'Percentage Increase',
                '+${p.shockPct.toStringAsFixed(1)}%',
                bold: true,
                color: const PdfColor(0.78, 0.16, 0.16)),
            _row2(
                p.isFr
                    ? 'Augmentation en dollars'
                    : p.isEs
                        ? 'Aumento en dólares'
                        : 'Dollar Increase',
                '+${cur2.format(p.dollarIncrease)}',
                bold: true),
            _row2(
                p.isFr
                    ? 'Intérêts totaux (remboursement)'
                    : p.isEs
                        ? 'Interés total (período pago)'
                        : 'Total Interest (repayment)',
                cur0.format(p.totalInterest)),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              p.isFr
                  ? 'PRÉPARATION'
                  : p.isEs
                      ? 'PREPARACIÓN'
                      : 'PREPARATION', [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
              child: pw.Text(
                p.isFr
                    ? 'Commence à épargner la différence (${cur2.format(p.dollarIncrease)}/mois) avant la fin de ta période de tirage.'
                    : p.isEs
                        ? 'Empieza a ahorrar la diferencia (${cur2.format(p.dollarIncrease)}/mes) antes de que termine el período de disposición.'
                        : 'Start saving the difference (${cur2.format(p.dollarIncrease)}/mo) before your draw period ends.',
                style: const pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey800),
              ),
            ),
          ]),
        ])),
      ]),
      pw.Spacer(),
      PdfBrandHelper.footer(ctx, 'HELOC Calculator'),
    ],
  );

  final pdf = pw.Document();
  pdf.addPage(pw.Page(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
    build: (ctx) => buildPage(ctx),
  ));
  return await pdf.save();
}

// ── Service class ────────────────────────────────────────────────────────────

class PdfExportService {
  static Future<void> exportHeloc({
    required BuildContext context,
    required double homeValue,
    required double mortgageBalance,
    required double homeEquity,
    required double creditLine,
    required double rate,
    required double drawPhaseMonths,
    required double repaymentMonths,
    required double interestOnlyPayment,
    required double repaymentPayment,
    required double totalInterest,
    double taxBracket = 22.0,
    bool isEs = false,
  }) async {
    final params = _HelocPdfParams(
      homeValue: homeValue,
      mortgageBalance: mortgageBalance,
      homeEquity: homeEquity,
      creditLine: creditLine,
      rate: rate,
      drawPhaseMonths: drawPhaseMonths,
      repaymentMonths: repaymentMonths,
      interestOnlyPayment: interestOnlyPayment,
      repaymentPayment: repaymentPayment,
      totalInterest: totalInterest,
      taxBracket: taxBracket,
      isEs: isEs,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final pdfBytes =
        await Isolate.run(() => _buildHelocPdf(params));
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_${creditLine.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  // ── Compare (HELOC vs Cash-Out Refi vs Personal Loan) ──────────────────

  static Future<void> exportCompare({
    required BuildContext context,
    required double drawAmount,
    required double helocRate,
    required int helocDrawYears,
    required int helocRepayYears,
    required double refiRate,
    required int refiTermYears,
    required double closingCosts,
    required double loanRate,
    required int loanTermYears,
    required double helocDrawPayment,
    required double helocRepayPayment,
    required double helocTotalInterest,
    required double refiMonthlyPayment,
    required double refiTotalInterest,
    required double loanMonthlyPayment,
    required double loanTotalInterest,
    required String bestOption,
    bool isEs = false,
    bool isFr = false,
  }) async {
    final params = _ComparePdfParams(
      drawAmount: drawAmount,
      helocRate: helocRate,
      helocDrawYears: helocDrawYears,
      helocRepayYears: helocRepayYears,
      refiRate: refiRate,
      refiTermYears: refiTermYears,
      closingCosts: closingCosts,
      loanRate: loanRate,
      loanTermYears: loanTermYears,
      helocDrawPayment: helocDrawPayment,
      helocRepayPayment: helocRepayPayment,
      helocTotalInterest: helocTotalInterest,
      refiMonthlyPayment: refiMonthlyPayment,
      refiTotalInterest: refiTotalInterest,
      loanMonthlyPayment: loanMonthlyPayment,
      loanTotalInterest: loanTotalInterest,
      bestOption: bestOption,
      isEs: isEs,
      isFr: isFr,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final pdfBytes =
        await Isolate.run(() => _buildComparePdf(params));
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_Compare_${drawAmount.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  // ── Draw Optimizer ───────────────────────────────────────────────────────

  static Future<void> exportDrawOptimizer({
    required BuildContext context,
    required double creditLimit,
    required double rate,
    required int drawYears,
    required int repayYears,
    required double totalDraw,
    required String optimalStrategy,
    required double yourPlanInterest,
    required double allAtOnceInterest,
    required double spreadEvenlyInterest,
    required double optimalTotalInterest,
    required double optimalDrawInterest,
    required double optimalBalanceAtDrawEnd,
    required int optimalPayoffMonths,
    bool isEs = false,
    bool isFr = false,
  }) async {
    final params = _DrawOptimizerPdfParams(
      creditLimit: creditLimit,
      rate: rate,
      drawYears: drawYears,
      repayYears: repayYears,
      totalDraw: totalDraw,
      optimalStrategy: optimalStrategy,
      yourPlanInterest: yourPlanInterest,
      allAtOnceInterest: allAtOnceInterest,
      spreadEvenlyInterest: spreadEvenlyInterest,
      optimalTotalInterest: optimalTotalInterest,
      optimalDrawInterest: optimalDrawInterest,
      optimalBalanceAtDrawEnd: optimalBalanceAtDrawEnd,
      optimalPayoffMonths: optimalPayoffMonths,
      isEs: isEs,
      isFr: isFr,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final pdfBytes =
        await Isolate.run(() => _buildDrawOptimizerPdf(params));
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_DrawOptimizer_${creditLimit.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  // ── HELOC vs Cash-Out Refi ───────────────────────────────────────────────

  static Future<void> exportHelocVsCashout({
    required BuildContext context,
    required double homeValue,
    required double existingBalance,
    required double existingRate,
    required int existingYears,
    required double cashNeeded,
    required double helocRate,
    required double refiRate,
    required double closingPct,
    required bool financeClosing,
    required double helocIOPayment,
    required double helocPIPayment,
    required double helocTotalMonthly,
    required double helocTotalInterest30y,
    required double refiNewBalance,
    required double refiMonthly,
    required double refiClosingCosts,
    required double refiTotalInterest30y,
    required double refiTotalCost,
    required int breakevenMonths,
    required int winnerIndex,
    bool isEs = false,
    bool isFr = false,
  }) async {
    final params = _HelocVsCashoutPdfParams(
      homeValue: homeValue,
      existingBalance: existingBalance,
      existingRate: existingRate,
      existingYears: existingYears,
      cashNeeded: cashNeeded,
      helocRate: helocRate,
      refiRate: refiRate,
      closingPct: closingPct,
      financeClosing: financeClosing,
      helocIOPayment: helocIOPayment,
      helocPIPayment: helocPIPayment,
      helocTotalMonthly: helocTotalMonthly,
      helocTotalInterest30y: helocTotalInterest30y,
      refiNewBalance: refiNewBalance,
      refiMonthly: refiMonthly,
      refiClosingCosts: refiClosingCosts,
      refiTotalInterest30y: refiTotalInterest30y,
      refiTotalCost: refiTotalCost,
      breakevenMonths: breakevenMonths,
      winnerIndex: winnerIndex,
      isEs: isEs,
      isFr: isFr,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final pdfBytes =
        await Isolate.run(() => _buildHelocVsCashoutPdf(params));
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_VsCashout_${cashNeeded.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  // ── Payment Shock ────────────────────────────────────────────────────────

  static Future<void> exportPaymentShock({
    required BuildContext context,
    required double helocBalance,
    required double currentRate,
    required double projectedRate,
    required int repayYears,
    required double ioPayment,
    required double piPayment,
    required double shockPct,
    required double dollarIncrease,
    required double totalInterest,
    bool isEs = false,
    bool isFr = false,
  }) async {
    final params = _PaymentShockPdfParams(
      helocBalance: helocBalance,
      currentRate: currentRate,
      projectedRate: projectedRate,
      repayYears: repayYears,
      ioPayment: ioPayment,
      piPayment: piPayment,
      shockPct: shockPct,
      dollarIncrease: dollarIncrease,
      totalInterest: totalInterest,
      isEs: isEs,
      isFr: isFr,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    final pdfBytes =
        await Isolate.run(() => _buildPaymentShockPdf(params));
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_PaymentShock_${helocBalance.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static Future<void> showUnlockOrPay(
      BuildContext context, Future<void> Function() onExport) async {
    if (freemiumService.hasFullAccess) {
      await onExport();
      return;
    }
    await PaywallHard.show(context, isSpanish: isSpanishNotifier.value);
  }
}
