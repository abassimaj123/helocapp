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
          content: Text(isSpanishNotifier.value
              ? 'Anuncio no disponible. Inténtalo más tarde.'
              : 'Ad not available. Try again later.')));
  }

  @override
  Widget build(BuildContext context) {
    final adReady = adService.isRewardedReady;
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
        Text(isEs ? 'Exportar PDF' : 'Export PDF',
            style: const TextStyle(
                fontSize: AppTextSize.subtitle, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
            isEs
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
                              isEs
                                  ? 'Ver un video corto'
                                  : 'Watch a short video',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: AppTextSize.bodyMd)),
                          const SizedBox(height: 2),
                          Text(
                              isEs
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
                  isEs
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
            child: Text(isEs ? 'Ahora no' : 'Not now',
                style: const TextStyle(color: Color(0xFF64748B)))),
      ]),
    );
  }
}
