import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../freemium/iap_service.dart';
import '../theme/app_theme.dart';
import '../../main.dart';
import 'package:calcwise_core/calcwise_core.dart';

const _teal = PdfColor(0.039, 0.475, 0.490); // HELOC teal
const _navy = PdfColor(0.059, 0.200, 0.350);
const _light = PdfColor(0.910, 0.965, 0.980);

class PdfExportService {
  static final _cur2 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  static final _cur0 =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  static final _date = DateFormat('MMMM d, yyyy');

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
    bool isEs = false,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) => _buildPage(
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
        isEs: isEs,
      ),
    ));
    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_${creditLine.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles(
        [XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _buildPage({
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
    bool isEs = false,
  }) {
    final now = DateTime.now();
    final ltv = homeValue > 0 ? (mortgageBalance / homeValue * 100) : 0.0;
    final drawYears = (drawPhaseMonths / 12).ceil().clamp(1, 10);

    // Build draw schedule rows (Year 1-5 interest-only during draw phase)
    final drawScheduleRows = <pw.TableRow>[];
    for (int yr = 1; yr <= drawYears.clamp(1, 5); yr++) {
      final annualInterest = creditLine * (rate / 100);
      drawScheduleRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
            color: yr.isOdd ? _light : PdfColors.white),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text('${isEs ? "Año" : "Year"} $yr',
                style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(_cur2.format(interestOnlyPayment),
                style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(_cur0.format(annualInterest),
                style: const pw.TextStyle(fontSize: 8)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: pw.Text(_cur0.format(creditLine),
                style: const pw.TextStyle(fontSize: 8, color: _teal)),
          ),
        ],
      ));
    }

    return pw
        .Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                      isEs
                          ? 'Calculadora HELOC'
                          : 'HELOC Calculator',
                      style: pw.TextStyle(
                          fontSize: AppTextSize.title,
                          fontWeight: pw.FontWeight.bold,
                          color: _teal)),
                  pw.Text(
                      isEs
                          ? 'Informe: Línea de Crédito sobre Valor Inmobiliario'
                          : 'Home Equity Line of Credit Report',
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.xs, color: PdfColors.grey700)),
                ]),
            pw.Text(_date.format(now),
                style:
                    const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
          ]),
      pw.Container(
          height: 2,
          color: _teal,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),
      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(isEs ? 'VALOR INMOBILIARIO' : 'HOME EQUITY', [
            _row2(isEs ? 'Valor de la vivienda' : 'Home Value',
                _cur0.format(homeValue)),
            _row2(isEs ? 'Saldo hipotecario' : 'Mortgage Balance',
                _cur0.format(mortgageBalance)),
            _row2(isEs ? 'Capital disponible' : 'Home Equity',
                _cur0.format(homeEquity),
                bold: true, color: _teal),
            _row2(isEs ? 'Ratio LTV' : 'LTV Ratio',
                '${ltv.toStringAsFixed(1)}%'),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(isEs ? 'CONDICIONES DEL HELOC' : 'HELOC TERMS', [
            _row2(isEs ? 'Línea de crédito' : 'Credit Line',
                _cur0.format(creditLine)),
            _row2(isEs ? 'Tasa de interés' : 'Interest Rate',
                '${rate.toStringAsFixed(2)}%'),
            _row2(isEs ? 'Período de disposición' : 'Draw Period',
                '${drawPhaseMonths.toStringAsFixed(0)} ${isEs ? "meses" : "months"}'),
            _row2(isEs ? 'Período de pago' : 'Repayment Period',
                '${repaymentMonths.toStringAsFixed(0)} ${isEs ? "meses" : "months"}'),
          ]),
        ])),
        pw.SizedBox(width: 14),
        pw.Expanded(
            child: pw.Column(children: [
          _sectionBox(
              isEs ? 'DESGLOSE DE PAGOS' : 'PAYMENT BREAKDOWN', [
            _row2(isEs ? 'Pago solo interés (disposición)' : 'Draw Phase Payment',
                _cur2.format(interestOnlyPayment)),
            _row2(isEs ? 'Pago mensual (amortización)' : 'Monthly Repayment',
                _cur2.format(repaymentPayment),
                bold: true, color: _navy),
            _row2(isEs ? 'Interés total' : 'Total Interest',
                _cur0.format(totalInterest)),
          ]),
          pw.SizedBox(height: 10),
          _sectionBox(
              isEs
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
                      decoration: const pw.BoxDecoration(color: _navy),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: pw.Text(isEs ? 'Año' : 'Year',
                              style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: pw.Text(isEs ? 'Pago/mes' : 'Payment/mo',
                              style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: pw.Text(isEs ? 'Interés/año' : 'Interest/yr',
                              style: pw.TextStyle(
                                  fontSize: 7,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 6, vertical: 3),
                          child: pw.Text(isEs ? 'Saldo' : 'Balance',
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
      pw.Column(children: [
        pw.Divider(color: PdfColors.grey300, height: 12),
        pw.Text(
            isEs
                ? 'Generado por HELOC Calculator · Solo para ilustración. No es consejo financiero.'
                : 'Generated by HELOC Calculator · For illustration purposes only. Not financial advice.',
            style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500)),
      ]),
    ]);
  }

  static pw.Widget _sectionBox(String title, List<pw.Widget> rows) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
              width: double.infinity,
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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

  static pw.Widget _row2(String label, String value,
          {bool bold = false, PdfColor? color}) =>
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label,
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey800)),
              pw.Text(value,
                  style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: color ?? PdfColors.black)),
            ]),
      );

  // ── Compare (HELOC vs Cash-Out Refi vs Personal Loan) ──────────────────────

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
    // Results
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) {
        final now = DateTime.now();
        final minTotal = [helocTotalInterest, refiTotalInterest, loanTotalInterest]
            .reduce((a, b) => a < b ? a : b);
        final winnerLabel = helocTotalInterest == minTotal
            ? 'HELOC'
            : (refiTotalInterest == minTotal
                ? (isFr ? 'Refi avec retrait' : isEs ? 'Refinanciación' : 'Cash-Out Refi')
                : (isFr ? 'Prêt personnel' : isEs ? 'Préstamo Personal' : 'Personal Loan'));

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(
                    isFr ? 'Comparaison de financement' : isEs ? 'Comparación de Financiamiento' : 'Financing Comparison',
                    style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _teal),
                  ),
                  pw.Text(
                    isFr ? 'HELOC vs Refi avec retrait vs Prêt personnel' : isEs ? 'HELOC vs Refinanciación vs Préstamo Personal' : 'HELOC vs Cash-Out Refi vs Personal Loan',
                    style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700),
                  ),
                ]),
                pw.Text(_date.format(now),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
            pw.Container(height: 2, color: _teal, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),

            // Inputs
            _sectionBox(isFr ? 'PARAMÈTRES' : isEs ? 'PARÁMETROS' : 'INPUTS', [
              _row2(isFr ? 'Montant à financer' : isEs ? 'Monto a financiar' : 'Amount to Finance', _cur0.format(drawAmount)),
              _row2(isFr ? 'Taux HELOC' : isEs ? 'Tasa HELOC' : 'HELOC Rate', '${helocRate.toStringAsFixed(2)}%'),
              _row2(isFr ? 'Période HELOC (disp/remb.)' : isEs ? 'Período HELOC (disp/pago)' : 'HELOC Period (draw/repay)',
                  '${helocDrawYears}y / ${helocRepayYears}y'),
              _row2(isFr ? 'Taux refi' : isEs ? 'Tasa Refi' : 'Refi Rate', '${refiRate.toStringAsFixed(2)}%'),
              _row2(isFr ? 'Durée refi' : isEs ? 'Plazo Refi' : 'Refi Term', '${refiTermYears}y'),
              _row2(isFr ? 'Frais de clôture refi' : isEs ? 'Costos cierre Refi' : 'Refi Closing Costs', _cur0.format(closingCosts)),
              _row2(isFr ? 'Taux prêt personnel' : isEs ? 'Tasa Préstamo Personal' : 'Personal Loan Rate', '${loanRate.toStringAsFixed(2)}%'),
              _row2(isFr ? 'Durée prêt personnel' : isEs ? 'Plazo Préstamo Personal' : 'Personal Loan Term', '${loanTermYears}y'),
            ]),
            pw.SizedBox(height: 10),

            // Comparison table
            _sectionBox(isFr ? 'COMPARAISON' : isEs ? 'COMPARACIÓN' : 'COMPARISON', [
              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(),
                  2: const pw.FlexColumnWidth(),
                  3: const pw.FlexColumnWidth(),
                },
                children: [
                  // Header row
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _navy),
                    children: [
                      _th(''),
                      _th('HELOC'),
                      _th(isFr ? 'Refi' : isEs ? 'Refi' : 'Cash-Out Refi'),
                      _th(isFr ? 'Prêt perso.' : isEs ? 'Préstamo' : 'Personal Loan'),
                    ],
                  ),
                  _tr3(isFr ? 'Paiement mensuel initial' : isEs ? 'Pago mensual inicial' : 'Monthly (initial)',
                      _cur2.format(helocDrawPayment),
                      _cur2.format(refiMonthlyPayment),
                      _cur2.format(loanMonthlyPayment),
                      oddRow: true),
                  _tr3(isFr ? 'Paiement mensuel (remb.)' : isEs ? 'Pago mensual (pago)' : 'Monthly (repayment)',
                      _cur2.format(helocRepayPayment),
                      _cur2.format(refiMonthlyPayment),
                      _cur2.format(loanMonthlyPayment)),
                  _tr3(isFr ? 'Intérêts totaux' : isEs ? 'Interés total' : 'Total Interest',
                      _cur0.format(helocTotalInterest),
                      _cur0.format(refiTotalInterest),
                      _cur0.format(loanTotalInterest),
                      oddRow: true, highlight: true),
                ],
              ),
            ]),
            pw.SizedBox(height: 10),

            // Recommendation
            _sectionBox(isFr ? 'RECOMMANDATION' : isEs ? 'RECOMENDACIÓN' : 'RECOMMENDATION', [
              _row2(isFr ? 'Meilleure option (intérêts totaux les plus bas)' : isEs ? 'Mejor opción (interés total mínimo)' : 'Best option (lowest total interest)',
                  winnerLabel, bold: true, color: _teal),
            ]),

            pw.Spacer(),
            pw.Column(children: [
              pw.Divider(color: PdfColors.grey300, height: 12),
              pw.Text(
                isFr
                    ? 'Généré par HELOC Calculator · À titre illustratif seulement. Pas un conseil financier.'
                    : isEs
                    ? 'Generado por HELOC Calculator · Solo para ilustración. No es consejo financiero.'
                    : 'Generated by HELOC Calculator · For illustration purposes only. Not financial advice.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
              ),
            ]),
          ],
        );
      },
    ));
    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_Compare_${drawAmount.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.Widget _th(String text) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
      );

  static pw.TableRow _tr3(String label, String v1, String v2, String v3,
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
                  fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: PdfColors.grey800)),
        ),
        ...[v1, v2, v3].map((v) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              child: pw.Text(v,
                  style: pw.TextStyle(
                      fontSize: 8,
                      fontWeight: highlight ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: highlight ? _teal : PdfColors.black)),
            )),
      ],
    );
  }

  // ── Draw Optimizer ───────────────────────────────────────────────────────────

  static Future<void> exportDrawOptimizer({
    required BuildContext context,
    required double creditLimit,
    required double rate,
    required int drawYears,
    required int repayYears,
    required double totalDraw,
    // Strategy results
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) {
        final now = DateTime.now();

        String _localLabel(String label) {
          if (isFr) {
            switch (label) {
              case 'Your Plan': return 'Mon plan';
              case 'All at Once': return 'Tout d\'un coup';
              case 'Spread Evenly': return 'Répartir';
              default: return label;
            }
          }
          if (!isEs) return label;
          switch (label) {
            case 'Your Plan': return 'Tu Plan';
            case 'All at Once': return 'Todo a la Vez';
            case 'Spread Evenly': return 'Distribuido';
            default: return label;
          }
        }

        final spreadSavings = allAtOnceInterest - spreadEvenlyInterest;

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(
                    isFr ? 'Optimiseur de période de tirage HELOC' : isEs ? 'Optimizador de Disposición HELOC' : 'HELOC Draw Period Optimizer',
                    style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _teal),
                  ),
                  pw.Text(
                    isFr ? 'Analyse des stratégies de tirage' : isEs ? 'Análisis de estrategias de disposición' : 'Draw strategy analysis',
                    style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700),
                  ),
                ]),
                pw.Text(_date.format(now),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
            pw.Container(height: 2, color: _teal, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),

            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Column(children: [
                _sectionBox(isFr ? 'PARAMÈTRES' : isEs ? 'PARÁMETROS' : 'INPUTS', [
                  _row2(isFr ? 'Limite de crédit' : isEs ? 'Límite de crédito' : 'Credit Limit', _cur0.format(creditLimit)),
                  _row2(isFr ? 'Total à tirer' : isEs ? 'Total a disponer' : 'Total Draw', _cur0.format(totalDraw)),
                  _row2(isFr ? 'Taux HELOC' : isEs ? 'Tasa HELOC' : 'HELOC Rate', '${rate.toStringAsFixed(2)}%'),
                  _row2(isFr ? 'Période de tirage' : isEs ? 'Período disposición' : 'Draw Period', '${drawYears}y'),
                  _row2(isFr ? 'Période de remboursement' : isEs ? 'Período de pago' : 'Repayment Period', '${repayYears}y'),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(isFr ? 'STRATÉGIE OPTIMALE' : isEs ? 'MEJOR ESTRATEGIA' : 'OPTIMAL STRATEGY', [
                  _row2(isFr ? 'Stratégie optimale' : isEs ? 'Estrategia óptima' : 'Optimal Strategy',
                      _localLabel(optimalStrategy), bold: true, color: _teal),
                  _row2(isFr ? 'Intérêts totaux' : isEs ? 'Interés total' : 'Total Interest',
                      _cur0.format(optimalTotalInterest), bold: true),
                  _row2(isFr ? 'Intérêts phase tirage' : isEs ? 'Interés fase disposición' : 'Draw Phase Interest',
                      _cur0.format(optimalDrawInterest)),
                  _row2(isFr ? 'Solde en fin de tirage' : isEs ? 'Balance al final de disposición' : 'Balance at Draw End',
                      _cur0.format(optimalBalanceAtDrawEnd)),
                  _row2(isFr ? 'Durée totale' : isEs ? 'Plazo total' : 'Payoff Timeline',
                      '${(optimalPayoffMonths / 12).toStringAsFixed(1)}y'),
                ]),
              ])),
              pw.SizedBox(width: 14),
              pw.Expanded(child: pw.Column(children: [
                _sectionBox(isFr ? 'COMPARAISON DES STRATÉGIES' : isEs ? 'COMPARACIÓN DE ESTRATEGIAS' : 'STRATEGY COMPARISON', [
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(2),
                      1: const pw.FlexColumnWidth(),
                    },
                    children: [
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(color: _navy),
                        children: [
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            child: pw.Text(isFr ? 'Stratégie' : isEs ? 'Estrategia' : 'Strategy',
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                          ),
                          pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            child: pw.Text(isFr ? 'Intérêts totaux' : isEs ? 'Interés total' : 'Total Interest',
                                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                          ),
                        ],
                      ),
                      _tr2Strategy(_localLabel('Your Plan'), _cur0.format(yourPlanInterest),
                          isOptimal: optimalStrategy == 'Your Plan', oddRow: true),
                      _tr2Strategy(_localLabel('All at Once'), _cur0.format(allAtOnceInterest),
                          isOptimal: optimalStrategy == 'All at Once'),
                      _tr2Strategy(_localLabel('Spread Evenly'), _cur0.format(spreadEvenlyInterest),
                          isOptimal: optimalStrategy == 'Spread Evenly', oddRow: true),
                    ],
                  ),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(isFr ? 'ÉCONOMIES POTENTIELLES' : isEs ? 'AHORRO POTENCIAL' : 'POTENTIAL SAVINGS', [
                  _row2(
                    isFr ? 'Économies (répartir vs tout d\'un coup)' : isEs ? 'Ahorro (distribuido vs todo a la vez)' : 'Savings (spread vs all at once)',
                    spreadSavings > 0 ? _cur0.format(spreadSavings) : '\$0',
                    bold: spreadSavings > 0, color: spreadSavings > 0 ? _teal : null,
                  ),
                ]),
              ])),
            ]),

            pw.Spacer(),
            pw.Column(children: [
              pw.Divider(color: PdfColors.grey300, height: 12),
              pw.Text(
                isFr
                    ? 'Généré par HELOC Calculator · À titre illustratif seulement. Pas un conseil financier.'
                    : isEs
                    ? 'Generado por HELOC Calculator · Solo para ilustración. No es consejo financiero.'
                    : 'Generated by HELOC Calculator · For illustration purposes only. Not financial advice.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
              ),
            ]),
          ],
        );
      },
    ));
    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_DrawOptimizer_${creditLimit.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static pw.TableRow _tr2Strategy(String label, String value,
      {required bool isOptimal, bool oddRow = false}) {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: oddRow ? _light : PdfColors.white),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Row(children: [
            if (isOptimal)
              pw.Container(
                width: 6, height: 6,
                decoration: const pw.BoxDecoration(color: _teal, shape: pw.BoxShape.circle),
                margin: const pw.EdgeInsets.only(right: 4),
              ),
            pw.Text(label,
                style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: isOptimal ? pw.FontWeight.bold : pw.FontWeight.normal,
                    color: isOptimal ? _teal : PdfColors.grey800)),
          ]),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: isOptimal ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: isOptimal ? _teal : PdfColors.black)),
        ),
      ],
    );
  }

  // ── HELOC vs Cash-Out Refi ───────────────────────────────────────────────────

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
    // Results
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
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) {
        final now = DateTime.now();
        final winnerLabel = winnerIndex == 0
            ? 'HELOC'
            : (isFr ? 'Refi avec retrait' : isEs ? 'Refi con Retiro' : 'Cash-Out Refi');

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(
                    isFr ? 'HELOC vs Refi avec retrait' : isEs ? 'HELOC vs Refinanciación con Retiro' : 'HELOC vs Cash-Out Refinance',
                    style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _teal),
                  ),
                  pw.Text(
                    isFr ? 'Comparaison des options d\'accès à la valeur nette' : isEs ? 'Comparación de opciones de acceso a capital' : 'Home equity access comparison',
                    style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700),
                  ),
                ]),
                pw.Text(_date.format(now),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
            pw.Container(height: 2, color: _teal, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),

            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Column(children: [
                _sectionBox(isFr ? 'PARAMÈTRES' : isEs ? 'PARÁMETROS' : 'INPUTS', [
                  _row2(isFr ? 'Valeur de la maison' : isEs ? 'Valor vivienda' : 'Home Value', _cur0.format(homeValue)),
                  _row2(isFr ? 'Solde hypothèque existante' : isEs ? 'Saldo hipoteca existente' : 'Existing Mortgage Balance', _cur0.format(existingBalance)),
                  _row2(isFr ? 'Taux hypothèque existante' : isEs ? 'Tasa hipoteca existente' : 'Existing Mortgage Rate', '${existingRate.toStringAsFixed(2)}%'),
                  _row2(isFr ? 'Années restantes hypothèque' : isEs ? 'Años restantes hipoteca' : 'Existing Mortgage Years Left', '${existingYears}y'),
                  _row2(isFr ? 'Liquidités nécessaires' : isEs ? 'Efectivo necesario' : 'Cash Needed', _cur0.format(cashNeeded)),
                  _row2(isFr ? 'Taux HELOC' : isEs ? 'Tasa HELOC' : 'HELOC Rate', '${helocRate.toStringAsFixed(2)}%'),
                  _row2(isFr ? 'Taux refi' : isEs ? 'Tasa Refi' : 'Refi Rate', '${refiRate.toStringAsFixed(2)}%'),
                  _row2(isFr ? 'Frais de clôture refi (%)' : isEs ? 'Costos cierre Refi (%)' : 'Refi Closing Costs (%)', '${closingPct.toStringAsFixed(1)}%'),
                  _row2(isFr ? 'Financer les frais de clôture' : isEs ? 'Financiar costos cierre' : 'Finance Closing Costs',
                      financeClosing ? (isFr ? 'Oui' : isEs ? 'Sí' : 'Yes') : 'No'),
                ]),
              ])),
              pw.SizedBox(width: 14),
              pw.Expanded(child: pw.Column(children: [
                _sectionBox('HELOC', [
                  _row2(isFr ? 'Paiement mensuel initial (int. seul.)' : isEs ? 'Pago mensual inicial (solo int.)' : 'Initial Monthly (interest-only)',
                      _cur2.format(helocTotalMonthly)),
                  _row2(isFr ? 'Paiement mensuel (remb.)' : isEs ? 'Pago mensual (fase pago)' : 'Monthly (repay phase)',
                      _cur2.format(helocPIPayment)),
                  _row2(isFr ? 'Frais initiaux' : isEs ? 'Costos iniciales' : 'Upfront Costs', r'$0'),
                  _row2(isFr ? 'Intérêts totaux 30 ans' : isEs ? 'Interés total 30 años' : 'Total Interest 30y',
                      _cur0.format(helocTotalInterest30y), bold: winnerIndex == 0, color: winnerIndex == 0 ? _teal : null),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(isFr ? 'REFI AVEC RETRAIT' : isEs ? 'REFI CON RETIRO' : 'CASH-OUT REFI', [
                  _row2(isFr ? 'Nouveau solde hypothèque' : isEs ? 'Nuevo saldo hipoteca' : 'New Mortgage Balance', _cur0.format(refiNewBalance)),
                  _row2(isFr ? 'Paiement mensuel' : isEs ? 'Pago mensual' : 'Monthly Payment', _cur2.format(refiMonthly)),
                  _row2(isFr ? 'Frais de clôture' : isEs ? 'Costos de cierre' : 'Closing Costs',
                      financeClosing ? (isFr ? 'Financés' : isEs ? 'Financiados' : 'Financed') : _cur0.format(refiClosingCosts)),
                  _row2(isFr ? 'Coût total' : isEs ? 'Costo total' : 'Total Cost',
                      _cur0.format(refiTotalCost), bold: winnerIndex == 1, color: winnerIndex == 1 ? _teal : null),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(isFr ? 'RÉSULTAT' : isEs ? 'RESULTADO' : 'OUTCOME', [
                  _row2(isFr ? 'Meilleure option' : isEs ? 'Mejor opción' : 'Best Option', winnerLabel, bold: true, color: _teal),
                  if (breakevenMonths < 9999)
                    _row2(isFr ? 'Seuil de rentabilité' : isEs ? 'Punto de equilibrio' : 'Break-Even',
                        '$breakevenMonths ${isFr ? "mois" : isEs ? "meses" : "months"} (~${(breakevenMonths / 12).toStringAsFixed(1)}y)'),
                ]),
              ])),
            ]),

            pw.Spacer(),
            pw.Column(children: [
              pw.Divider(color: PdfColors.grey300, height: 12),
              pw.Text(
                isFr
                    ? 'Généré par HELOC Calculator · À titre illustratif seulement. Pas un conseil financier.'
                    : isEs
                    ? 'Generado por HELOC Calculator · Solo para ilustración. No es consejo financiero.'
                    : 'Generated by HELOC Calculator · For illustration purposes only. Not financial advice.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
              ),
            ]),
          ],
        );
      },
    ));
    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_VsCashout_${cashNeeded.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  // ── Payment Shock ────────────────────────────────────────────────────────────

  static Future<void> exportPaymentShock({
    required BuildContext context,
    required double helocBalance,
    required double currentRate,
    required double projectedRate,
    required int repayYears,
    // Results
    required double ioPayment,
    required double piPayment,
    required double shockPct,
    required double dollarIncrease,
    required double totalInterest,
    bool isEs = false,
    bool isFr = false,
  }) async {
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 28),
      build: (_) {
        final now = DateTime.now();

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(
                    isFr ? 'Calculatrice de choc de paiement HELOC' : isEs ? 'Calculadora de Choque de Pago HELOC' : 'HELOC Payment Shock Calculator',
                    style: pw.TextStyle(fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold, color: _teal),
                  ),
                  pw.Text(
                    isFr ? 'Projection du paiement à la fin de la période de tirage' : isEs ? 'Proyección del pago al final del período de disposición' : 'Payment projection at end of draw period',
                    style: const pw.TextStyle(fontSize: AppTextSize.xs, color: PdfColors.grey700),
                  ),
                ]),
                pw.Text(_date.format(now),
                    style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600)),
              ],
            ),
            pw.Container(height: 2, color: _teal, margin: const pw.EdgeInsets.only(top: 6, bottom: 14)),

            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Column(children: [
                _sectionBox(isFr ? 'PARAMÈTRES' : isEs ? 'PARÁMETROS' : 'INPUTS', [
                  _row2(isFr ? 'Solde HELOC' : isEs ? 'Saldo HELOC' : 'HELOC Balance', _cur0.format(helocBalance)),
                  _row2(isFr ? 'Taux actuel (période de tirage)' : isEs ? 'Tasa actual (período disposición)' : 'Current Rate (draw period)', '${currentRate.toStringAsFixed(2)}%'),
                  _row2(isFr ? 'Taux projeté (période de remb.)' : isEs ? 'Tasa proyectada (período pago)' : 'Projected Rate (repayment period)', '${projectedRate.toStringAsFixed(2)}%'),
                  _row2(isFr ? 'Période de remboursement' : isEs ? 'Período de pago' : 'Repayment Period', '${repayYears}y'),
                ]),
              ])),
              pw.SizedBox(width: 14),
              pw.Expanded(child: pw.Column(children: [
                _sectionBox(isFr ? 'PAIEMENTS' : isEs ? 'PAGOS' : 'PAYMENTS', [
                  _row2(isFr ? 'Paiement actuel (int. seul.)' : isEs ? 'Pago actual (solo interés)' : 'Current Payment (interest-only)',
                      _cur2.format(ioPayment)),
                  _row2(isFr ? 'Nouveau paiement (C + I)' : isEs ? 'Nuevo pago (P + I)' : 'New Payment (P + I)',
                      _cur2.format(piPayment), bold: true, color: const PdfColor(0.78, 0.16, 0.16)),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(isFr ? 'CHOC DE PAIEMENT' : isEs ? 'CHOQUE DE PAGO' : 'PAYMENT SHOCK', [
                  _row2(isFr ? 'Augmentation en pourcentage' : isEs ? 'Aumento porcentual' : 'Percentage Increase',
                      '+${shockPct.toStringAsFixed(1)}%', bold: true, color: const PdfColor(0.78, 0.16, 0.16)),
                  _row2(isFr ? 'Augmentation en dollars' : isEs ? 'Aumento en dólares' : 'Dollar Increase',
                      '+${_cur2.format(dollarIncrease)}', bold: true),
                  _row2(isFr ? 'Intérêts totaux (remboursement)' : isEs ? 'Interés total (período pago)' : 'Total Interest (repayment)',
                      _cur0.format(totalInterest)),
                ]),
                pw.SizedBox(height: 10),
                _sectionBox(isFr ? 'PRÉPARATION' : isEs ? 'PREPARACIÓN' : 'PREPARATION', [
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
                    child: pw.Text(
                      isFr
                          ? 'Commence à épargner la différence (${_cur2.format(dollarIncrease)}/mois) avant la fin de ta période de tirage.'
                          : isEs
                          ? 'Empieza a ahorrar la diferencia (${_cur2.format(dollarIncrease)}/mes) antes de que termine el período de disposición.'
                          : 'Start saving the difference (${_cur2.format(dollarIncrease)}/mo) before your draw period ends.',
                      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey800),
                    ),
                  ),
                ]),
              ])),
            ]),

            pw.Spacer(),
            pw.Column(children: [
              pw.Divider(color: PdfColors.grey300, height: 12),
              pw.Text(
                isFr
                    ? 'Généré par HELOC Calculator · À titre illustratif seulement. Pas un conseil financier.'
                    : isEs
                    ? 'Generado por HELOC Calculator · Solo para ilustración. No es consejo financiero.'
                    : 'Generated by HELOC Calculator · For illustration purposes only. Not financial advice.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey500),
              ),
            ]),
          ],
        );
      },
    ));
    final pdfBytes = await pdf.save();
    final tmpDir = await getTemporaryDirectory();
    final pdfFile = File(
        '${tmpDir.path}/HELOC_PaymentShock_${helocBalance.round()}_${DateTime.now().millisecondsSinceEpoch}.pdf');
    await pdfFile.writeAsBytes(pdfBytes);
    await Share.shareXFiles([XFile(pdfFile.path, mimeType: 'application/pdf')]);
  }

  static Future<void> showUnlockOrPay(
      BuildContext context, Future<void> Function() onExport) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PdfUnlockSheet(onExport: onExport),
    );
  }
}

class _PdfUnlockSheet extends StatefulWidget {
  final Future<void> Function() onExport;
  const _PdfUnlockSheet({required this.onExport});
  @override
  State<_PdfUnlockSheet> createState() => _PdfUnlockSheetState();
}

class _PdfUnlockSheetState extends State<_PdfUnlockSheet> {
  bool _loading = false;
  Future<void> _watchAd() async {
    setState(() => _loading = true);
    final earned = await adService.showRewarded();
    if (!mounted) return;
    setState(() => _loading = false);
    if (earned) {
      Navigator.pop(context);
      await widget.onExport();
    } else
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isFrenchNotifier.value
              ? 'Publicité non disponible. Réessaie plus tard.'
              : isSpanishNotifier.value
              ? 'Anuncio no disponible. Inténtalo más tarde.'
              : 'Ad not available. Try again later.')));
  }

  @override
  Widget build(BuildContext context) {
    final adReady = adService.isRewardedReady;
    final isFr = isFrenchNotifier.value;
    final isEs = isSpanishNotifier.value;
    return Padding(
      padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        const Icon(Icons.picture_as_pdf_rounded,
            size: 36, color: AppTheme.primary),
        const SizedBox(height: 12),
        Text(isFr ? 'Exporter PDF' : isEs ? 'Exportar PDF' : 'Export PDF',
            style: const TextStyle(
                fontSize: AppTextSize.subtitle, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
            isFr
                ? 'Choisissez comment débloquer l\'export'
                : isEs
                ? 'Elige cómo desbloquear la exportación'
                : 'Choose how to unlock PDF export',
            style: const TextStyle(
                fontSize: AppTextSize.md, color: Color(0xFF475569))),
        const SizedBox(height: 24),
        Opacity(
            opacity: adReady ? 1.0 : 0.45,
            child: InkWell(
                onTap: (adReady && !_loading) ? _watchAd : null,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.3)),
                      borderRadius: BorderRadius.circular(AppRadius.xl)),
                  child: Row(children: [
                    Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.play_circle_outline,
                            color: AppTheme.primary, size: 24)),
                    const SizedBox(width: 14),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              isFr
                                  ? 'Regarder une courte vidéo'
                                  : isEs
                                  ? 'Ver un video corto'
                                  : 'Watch a short video',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: AppTextSize.bodyMd)),
                          const SizedBox(height: 2),
                          Text(
                              isFr
                                  ? 'Exporter une fois — gratuit'
                                  : isEs
                                  ? 'Exportar una vez — gratis'
                                  : 'Export once — free',
                              style: const TextStyle(
                                  color: Color(0xFF475569),
                                  fontSize: AppTextSize.md)),
                        ])),
                    if (_loading)
                      const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                    else
                      const Icon(Icons.chevron_right_rounded,
                          color: Color(0xFF94A3B8)),
                  ]),
                ))),
        const SizedBox(height: 12),
        SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                IAPService.instance.buy();
              },
              icon: const Icon(Icons.workspace_premium, size: 18),
              label: Text(
                  isFr
                      ? 'Premium (illimité)'
                      : isEs
                      ? 'Premium (ilimitado)'
                      : 'Premium (unlimited)',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.xl))),
            )),
        const SizedBox(height: 10),
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isFr ? 'Pas maintenant' : isEs ? 'Ahora no' : 'Not now',
                style: const TextStyle(color: Color(0xFF64748B)))),
      ]),
    );
  }
}
