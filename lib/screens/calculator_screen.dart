import 'dart:math' show pow;

import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../core/db/database_service.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/heloc_engine.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';
import '../widgets/insight_card.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../widgets/premium_cta_widget.dart';
import '../widgets/result_card.dart';
import '../core/insight_engine.dart';
import 'compare_screen.dart';
import 'draw_optimizer_screen.dart';
import 'heloc_vs_cashout_screen.dart';
import 'payment_shock_screen.dart';

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

double _parseNum(String v) {
  if (v.isEmpty) return 0.0;
  final s = (v.contains('.') && v.contains(','))
      ? v.replaceAll(',', '')
      : v.replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

/// Payment mode selected by the IO vs P&I toggle.
enum _PaymentMode { interestOnly, fullPI }

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _formKey = GlobalKey<FormState>();

  final _homeValueCtrl = TextEditingController(text: '400000');
  final _mortgageCtrl = TextEditingController(text: '250000');
  final _drawCtrl = TextEditingController(text: '100000');
  final _rateCtrl = TextEditingController(text: '8.5');
  final _drawYearsCtrl = TextEditingController(text: '10');
  final _repayYearsCtrl = TextEditingController(text: '20');

  final _fmt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _fmtDec =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtPct = NumberFormat('##0.0#');

  // Live computed equity
  double _availableEquity = 200000;
  double _ltvPct = 40;

  // IO vs P&I toggle
  _PaymentMode _paymentMode = _PaymentMode.interestOnly;

  Map<String, dynamic>? _results;
  List<Map<String, dynamic>>? _cachedScenarios;

  @override
  void initState() {
    super.initState();
    _homeValueCtrl.addListener(_updateEquity);
    _mortgageCtrl.addListener(_updateEquity);
    for (final c in [
      _homeValueCtrl,
      _mortgageCtrl,
      _drawCtrl,
      _rateCtrl,
      _drawYearsCtrl,
      _repayYearsCtrl
    ]) {
      c.addListener(_tryCalculate);
    }
    _updateEquity();
    // Run initial calculation with default values
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCalculate());
  }

  void _updateEquity() {
    final homeValue = _parseNum(_homeValueCtrl.text);
    final mortgage = _parseNum(_mortgageCtrl.text);
    final equity = HelocEngine.availableEquity(homeValue, mortgage);
    final ltv = HelocEngine.ltv(mortgage, homeValue);
    if (mounted)
      setState(() {
        _availableEquity = equity;
        _ltvPct = ltv;
      });
  }

  void _tryCalculate() {
    final homeValue = _parseNum(_homeValueCtrl.text);
    final mortgage = _parseNum(_mortgageCtrl.text);
    final draw = _parseNum(_drawCtrl.text);
    final rate = _parseNum(_rateCtrl.text);
    final drawYears = int.tryParse(_drawYearsCtrl.text) ?? 0;
    final repayYears = int.tryParse(_repayYearsCtrl.text) ?? 0;
    if (homeValue <= 0 ||
        draw <= 0 ||
        rate <= 0 ||
        drawYears <= 0 ||
        repayYears <= 0) return;
    final equity = HelocEngine.availableEquity(homeValue, mortgage);
    final ltv = HelocEngine.ltv(mortgage, homeValue);
    final interestOnly = HelocEngine.interestOnlyPayment(draw, rate);
    final repayment = HelocEngine.amortizedPayment(draw, rate, repayYears);
    final totalInterest =
        HelocEngine.totalInterestPaid(draw, rate, drawYears, repayYears);
    final maxBorrow85 =
        HelocEngine.maxBorrowCapacity(homeValue, mortgage, ltvLimit: 0.85);
    final taxSavings = HelocEngine.estimatedAnnualTaxSavings(draw, rate, 22.0);
    // Full P&I: amortize over combined term from day 1
    final fullTotalMonths = (drawYears + repayYears) * 12;
    final fullTermYears = fullTotalMonths ~/ 12;
    final fullPI = HelocEngine.amortizedPayment(
        draw, rate, fullTermYears > 0 ? fullTermYears : 1);
    final totalInterestFullPI = HelocEngine.totalInterestFullAmortizing(
        draw, rate, drawYears, repayYears);
    if (!mounted) return;
    setState(() {
      _results = {
        'homeValue': homeValue,
        'mortgage': mortgage,
        'draw': draw,
        'rate': rate,
        'drawYears': drawYears,
        'repayYears': repayYears,
        'equity': equity,
        'ltv': ltv,
        'interestOnly': interestOnly,
        'repayment': repayment,
        'totalInterest': totalInterest,
        'maxBorrow85': maxBorrow85,
        'taxSavings': taxSavings,
        'fullPI': fullPI,
        'totalInterestFullPI': totalInterestFullPI,
      };
      _cachedScenarios = _computeScenarioData(
          draw: draw,
          baseRate: rate,
          drawYears: drawYears,
          repayYears: repayYears);
    });
  }

  /// Computes rate scenario rows without touching the widget tree.
  List<Map<String, dynamic>> _computeScenarioData({
    required double draw,
    required double baseRate,
    required int drawYears,
    required int repayYears,
  }) {
    const offsets = [-1, 0, 1];
    return offsets.map((offset) {
      final scenarioRate = (baseRate + offset).clamp(0.01, 100.0);
      return {
        'offset': offset,
        'scenarioRate': scenarioRate,
        'drawPmt': HelocEngine.interestOnlyPayment(draw, scenarioRate),
        'repayPmt':
            HelocEngine.amortizedPayment(draw, scenarioRate, repayYears),
        'totalInt': HelocEngine.totalInterestPaid(
            draw, scenarioRate, drawYears, repayYears),
      };
    }).toList();
  }

  @override
  void dispose() {
    _homeValueCtrl.removeListener(_updateEquity);
    _mortgageCtrl.removeListener(_updateEquity);
    for (final c in [
      _homeValueCtrl,
      _mortgageCtrl,
      _drawCtrl,
      _rateCtrl,
      _drawYearsCtrl,
      _repayYearsCtrl
    ]) {
      c.removeListener(_tryCalculate);
    }
    _homeValueCtrl.dispose();
    _mortgageCtrl.dispose();
    _drawCtrl.dispose();
    _rateCtrl.dispose();
    _drawYearsCtrl.dispose();
    _repayYearsCtrl.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    if (!_formKey.currentState!.validate()) return;
    final homeValue = _parseNum(_homeValueCtrl.text);
    final mortgage = _parseNum(_mortgageCtrl.text);
    final draw = _parseNum(_drawCtrl.text);
    final rate = _parseNum(_rateCtrl.text);
    final drawYears = int.tryParse(_drawYearsCtrl.text) ?? 10;
    final repayYears = int.tryParse(_repayYearsCtrl.text) ?? 20;

    final equity = HelocEngine.availableEquity(homeValue, mortgage);
    final ltv = HelocEngine.ltv(mortgage, homeValue);
    final interestOnly = HelocEngine.interestOnlyPayment(draw, rate);
    final repayment = HelocEngine.amortizedPayment(draw, rate, repayYears);
    final totalInterest =
        HelocEngine.totalInterestPaid(draw, rate, drawYears, repayYears);
    final maxBorrow85 =
        HelocEngine.maxBorrowCapacity(homeValue, mortgage, ltvLimit: 0.85);
    final taxSavings = HelocEngine.estimatedAnnualTaxSavings(draw, rate, 22.0);
    final fullTotalMonths = (drawYears + repayYears) * 12;
    final fullTermYears = fullTotalMonths ~/ 12;
    final fullPI = HelocEngine.amortizedPayment(
        draw, rate, fullTermYears > 0 ? fullTermYears : 1);
    final totalInterestFullPI = HelocEngine.totalInterestFullAmortizing(
        draw, rate, drawYears, repayYears);

    setState(() {
      _results = {
        'homeValue': homeValue,
        'mortgage': mortgage,
        'draw': draw,
        'rate': rate,
        'drawYears': drawYears,
        'repayYears': repayYears,
        'equity': equity,
        'ltv': ltv,
        'interestOnly': interestOnly,
        'repayment': repayment,
        'totalInterest': totalInterest,
        'maxBorrow85': maxBorrow85,
        'taxSavings': taxSavings,
        'fullPI': fullPI,
        'totalInterestFullPI': totalInterestFullPI,
      };
      _cachedScenarios = _computeScenarioData(
          draw: draw,
          baseRate: rate,
          drawYears: drawYears,
          repayYears: repayYears);
    });

    AnalyticsService.instance.logCalculation(
      homeValue: homeValue,
      ratePct: rate,
    );
    final trigger = await paywallSession.recordAction();
    if (trigger != PaywallTrigger.none &&
        mounted &&
        !freemiumService.hasFullAccess) {
      if (trigger == PaywallTrigger.soft) {
        PaywallSoft.show(context);
      } else {
        PaywallHard.show(context);
      }
    }

    HapticFeedback.mediumImpact();
    try {
      await DatabaseService.instance.insertHistory(
        inputs: {
          'homeValue': homeValue,
          'balance': mortgage,
          'draw': draw,
          'rate': rate,
          'drawYears': drawYears,
          'repayYears': repayYears,
        },
        results: {
          'equity': equity,
          'ltv': ltv,
          'interestOnly': interestOnly,
          'repayment': repayment,
        },
      );
    } catch (_) {}
    adService.onSave();
  }

  Future<void> _saveToHistory() async {
    if (_results == null) return;
    final homeValue = (_results!['homeValue'] as double?) ?? 0;
    final mortgage = (_results!['mortgage'] as double?) ?? 0;
    final draw = (_results!['draw'] as double?) ?? 0;
    final rate = (_results!['rate'] as double?) ?? 0;
    final drawYears = (_results!['drawYears'] as int?) ?? 10;
    final repayYears = (_results!['repayYears'] as int?) ?? 20;
    final equity = (_results!['equity'] as double?) ?? 0;
    final ltv = (_results!['ltv'] as double?) ?? 0;
    final interestOnly = (_results!['interestOnly'] as double?) ?? 0;
    final repayment = (_results!['repayment'] as double?) ?? 0;

    HapticFeedback.mediumImpact();
    try {
      await DatabaseService.instance.insertHistory(
        inputs: {
          'homeValue': homeValue,
          'balance': mortgage,
          'draw': draw,
          'rate': rate,
          'drawYears': drawYears,
          'repayYears': repayYears,
        },
        results: {
          'equity': equity,
          'ltv': ltv,
          'interestOnly': interestOnly,
          'repayment': repayment,
        },
      );
    } catch (_) {}
    adService.onSave();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(_isEs() ? 'Guardado en historial' : 'Saved to history')),
      );
    }
  }

  bool _isEs() {
    // Reads the current locale preference without requiring BuildContext.
    try {
      return Localizations.localeOf(context).languageCode == 'es';
    } catch (_) {
      return false;
    }
  }

  void _reset() {
    _homeValueCtrl.text = '400000';
    _mortgageCtrl.text = '250000';
    _drawCtrl.text = '100000';
    _rateCtrl.text = '8.5';
    _drawYearsCtrl.text = '10';
    _repayYearsCtrl.text = '20';
    setState(() => _results = null);
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  Future<void> _share(bool isEs) async {
    if (_results == null) return;

    if (!freemiumService.hasFullAccess) {
      final trigger = await paywallSession.recordAction();
      if (trigger == PaywallTrigger.hard) {
        PaywallHard.show(context);
        return;
      } else if (trigger == PaywallTrigger.soft) {
        PaywallSoft.show(context);
        // share anyway (soft paywall)
      }
    }

    final text = _buildShareText(isEs);
    try {
      await Share.share(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(isEs ? 'Compartido con éxito' : 'Shared successfully'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEs ? 'Error al compartir' : 'Export failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _buildShareText(bool isEs) {
    final r = _results!;
    final homeValue = (r['homeValue'] as num?)?.toDouble() ?? 0.0;
    final mortgage = (r['mortgage'] as num?)?.toDouble() ?? 0.0;
    final draw = (r['draw'] as num?)?.toDouble() ?? 0.0;
    final rate = (r['rate'] as num?)?.toDouble() ?? 0.0;
    final drawYears = (r['drawYears'] as num?)?.toInt() ?? 10;
    final repayYears = (r['repayYears'] as num?)?.toInt() ?? 20;
    final equity = (r['equity'] as num?)?.toDouble() ?? 0.0;
    final ltv = (r['ltv'] as num?)?.toDouble() ?? 0.0;
    final interestOnly = (r['interestOnly'] as num?)?.toDouble() ?? 0.0;
    final repayment = (r['repayment'] as num?)?.toDouble() ?? 0.0;
    final taxSavings = (r['taxSavings'] as num?)?.toDouble() ?? 0.0;

    if (isEs) {
      return '''
HELOC Calculator — Resultado

Valor vivienda: ${_fmt.format(homeValue)}
Saldo hipoteca: ${_fmt.format(mortgage)}
Monto dispuesto: ${_fmt.format(draw)}
Tasa HELOC: ${rate.toStringAsFixed(2)}%
Período: ${drawYears}a disposición / ${repayYears}a pago

Pago solo interés: ${_fmtDec.format(interestOnly)}/mes
Pago amortizado: ${_fmtDec.format(repayment)}/mes
Capital disponible: ${_fmt.format(equity)}
LTV actual: ${_fmtPct.format(ltv)}%
Ahorro fiscal estimado: ${_fmtDec.format(taxSavings)}/año

⚠ Consulta a un asesor fiscal. Los intereses del HELOC pueden ser deducibles si se usan para mejoras del hogar.
''';
    }
    return '''
HELOC Calculator — Results

Home Value: ${_fmt.format(homeValue)}
Mortgage Balance: ${_fmt.format(mortgage)}
Draw Amount: ${_fmt.format(draw)}
HELOC Rate: ${rate.toStringAsFixed(2)}%
Period: ${drawYears}yr draw / ${repayYears}yr repayment

Interest-Only Payment: ${_fmtDec.format(interestOnly)}/mo
Repayment Payment: ${_fmtDec.format(repayment)}/mo
Available Equity: ${_fmt.format(equity)}
Current LTV: ${_fmtPct.format(ltv)}%
Est. Tax Savings: ${_fmtDec.format(taxSavings)}/yr

⚠ Consult a tax advisor. HELOC interest may be deductible if used for home improvements.
''';
  }

  // ── PDF Export ─────────────────────────────────────────────────────────────

  Future<void> _exportPdf(bool isEs) async {
    if (_results == null) return;

    if (!freemiumService.hasFullAccess) {
      await PaywallHard.show(context);
      return;
    }

    AnalyticsService.instance.logPdfExported();
    try {
      final bytes = await _buildPdf(isEs);
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'HELOC_Calculator_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                isEs ? 'PDF exportado con éxito' : 'PDF exported successfully'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEs ? 'Error al exportar PDF' : 'Export failed'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<Uint8List> _buildPdf(bool isEs) async {
    final r = _results!;
    final homeValue = (r['homeValue'] as num?)?.toDouble() ?? 0.0;
    final mortgage = (r['mortgage'] as num?)?.toDouble() ?? 0.0;
    final draw = (r['draw'] as num?)?.toDouble() ?? 0.0;
    final rate = (r['rate'] as num?)?.toDouble() ?? 0.0;
    final drawYears = (r['drawYears'] as num?)?.toInt() ?? 10;
    final repayYears = (r['repayYears'] as num?)?.toInt() ?? 20;
    final equity = (r['equity'] as num?)?.toDouble() ?? 0.0;
    final ltv = (r['ltv'] as num?)?.toDouble() ?? 0.0;
    final interestOnly = (r['interestOnly'] as num?)?.toDouble() ?? 0.0;
    final repayment = (r['repayment'] as num?)?.toDouble() ?? 0.0;
    final taxSavings = (r['taxSavings'] as num?)?.toDouble() ?? 0.0;
    final now = DateTime.now();
    final dateFmt = DateFormat('MMM d, yyyy');

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Container(
                padding: const pw.EdgeInsets.all(AppSpacing.lg),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF00695C),
                  borderRadius: pw.BorderRadius.circular(AppRadius.md),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'HELOC Calculator',
                      style: pw.TextStyle(
                        fontSize: AppTextSize.title,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      dateFmt.format(now),
                      style: const pw.TextStyle(
                          fontSize: AppTextSize.sm, color: PdfColors.white),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 24),

              // Inputs
              _pdfSectionTitle(isEs ? 'Datos de Entrada' : 'Input Parameters'),
              pw.SizedBox(height: 8),
              _pdfTable(
                isEs
                    ? [
                        ['Valor de la vivienda', _fmt.format(homeValue)],
                        ['Saldo hipotecario', _fmt.format(mortgage)],
                        ['Monto a disponer', _fmt.format(draw)],
                        ['Tasa HELOC', '${rate.toStringAsFixed(2)}%'],
                        ['Período de disposición', '$drawYears años'],
                        ['Período de pago', '$repayYears años'],
                      ]
                    : [
                        ['Home Value', _fmt.format(homeValue)],
                        ['Mortgage Balance', _fmt.format(mortgage)],
                        ['Draw Amount', _fmt.format(draw)],
                        ['HELOC Rate', '${rate.toStringAsFixed(2)}%'],
                        ['Draw Period', '$drawYears years'],
                        ['Repayment Period', '$repayYears years'],
                      ],
              ),
              pw.SizedBox(height: 20),

              // Results
              _pdfSectionTitle(isEs ? 'Resultados' : 'Results'),
              pw.SizedBox(height: 8),
              _pdfTable(
                isEs
                    ? [
                        [
                          'Pago solo interés (período disposición)',
                          _fmtDec.format(interestOnly)
                        ],
                        [
                          'Pago amortizado (período de pago)',
                          _fmtDec.format(repayment)
                        ],
                        ['Capital disponible (85% LTV)', _fmt.format(equity)],
                        ['LTV actual', '${_fmtPct.format(ltv)}%'],
                        [
                          'Ahorro fiscal estimado (22%)',
                          '${_fmtDec.format(taxSavings)}/año'
                        ],
                      ]
                    : [
                        [
                          'Interest-Only Payment (Draw Period)',
                          _fmtDec.format(interestOnly)
                        ],
                        [
                          'Repayment Payment (After Draw)',
                          _fmtDec.format(repayment)
                        ],
                        ['Available Equity (85% LTV)', _fmt.format(equity)],
                        ['Current LTV', '${_fmtPct.format(ltv)}%'],
                        [
                          'Est. Tax Savings (22% bracket)',
                          '${_fmtDec.format(taxSavings)}/year'
                        ],
                      ],
                highlightFirst: true,
              ),
              pw.SizedBox(height: 20),

              // Tax deductibility note
              pw.Container(
                padding: const pw.EdgeInsets.all(AppSpacing.md),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFE3F2FD),
                  borderRadius: pw.BorderRadius.circular(AppRadius.sm),
                  border: pw.Border.all(
                      color: const PdfColor.fromInt(0xFF1565C0), width: 0.5),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      isEs
                          ? 'Nota sobre Deducibilidad Fiscal'
                          : 'Tax Deductibility Note',
                      style: pw.TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: pw.FontWeight.bold,
                        color: const PdfColor.fromInt(0xFF1565C0),
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      isEs
                          ? 'Los intereses del HELOC pueden ser deducibles de impuestos si los fondos se utilizan para mejoras sustanciales del hogar. El ahorro fiscal estimado se basa en un tramo impositivo del 22%. Consulte a un asesor fiscal calificado.'
                          : 'HELOC interest may be tax-deductible when funds are used for substantial home improvements. Estimated tax savings are based on the 22% tax bracket. Consult a qualified tax advisor.',
                      style: const pw.TextStyle(
                          fontSize: 10, color: PdfColor.fromInt(0xFF1565C0)),
                    ),
                  ],
                ),
              ),
              pw.Spacer(),

              // Disclaimer
              pw.Divider(color: PdfColors.grey300),
              pw.SizedBox(height: 6),
              pw.Text(
                isEs
                    ? 'Aviso legal: Este informe es solo para fines informativos y no constituye asesoramiento financiero, fiscal ni legal. Los resultados son estimaciones y pueden variar. Consulte a profesionales calificados antes de tomar decisiones financieras.'
                    : 'Disclaimer: This report is for informational purposes only and does not constitute financial, tax, or legal advice. Results are estimates and may vary. Consult qualified professionals before making financial decisions.',
                style:
                    const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
              ),
            ],
          );
        },
      ),
    );
    return doc.save();
  }

  pw.Widget _pdfSectionTitle(String title) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6, horizontal: 10),
      decoration: pw.BoxDecoration(
        color: const PdfColor.fromInt(0xFFE8F5E9),
        borderRadius: pw.BorderRadius.circular(AppRadius.xs),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: AppTextSize.md,
          fontWeight: pw.FontWeight.bold,
          color: const PdfColor.fromInt(0xFF00695C),
        ),
      ),
    );
  }

  pw.Widget _pdfTable(List<List<String>> rows, {bool highlightFirst = false}) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
      },
      children: rows.asMap().entries.map((e) {
        final isFirst = e.key == 0 && highlightFirst;
        return pw.TableRow(
          decoration: isFirst
              ? const pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8F5E9))
              : (e.key % 2 == 0
                  ? const pw.BoxDecoration(color: PdfColors.white)
                  : const pw.BoxDecoration(
                      color: PdfColor.fromInt(0xFFF5F5F5))),
          children: [
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: pw.Text(e.value[0],
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
            pw.Padding(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: pw.Text(
                e.value[1],
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight:
                      isFirst ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: isFirst
                      ? const PdfColor.fromInt(0xFF00695C)
                      : PdfColors.black,
                ),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: CalcwisePageEntrance(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isEs
                                ? 'Información de la Vivienda'
                                : 'Home Information',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.bodyLg),
                          ),
                          const SizedBox(height: 16),

                          _buildField(
                            controller: _homeValueCtrl,
                            label: isEs
                                ? 'Valor de la vivienda (\$)'
                                : 'Home Value (\$)',
                            hint: '500000',
                            isCurrency: true,
                            validator: (v) => _parseNum(v ?? '') <= 0
                                ? (isEs ? 'Ingresa un valor' : 'Enter a value')
                                : null,
                          ),
                          const SizedBox(height: 16),

                          _buildField(
                            controller: _mortgageCtrl,
                            label: isEs
                                ? 'Saldo hipotecario actual (\$)'
                                : 'Current Mortgage Balance (\$)',
                            hint: '200000',
                            isCurrency: true,
                            validator: (v) => _parseNum(v ?? '') < 0
                                ? (isEs ? 'Valor inválido' : 'Invalid value')
                                : null,
                          ),
                          const SizedBox(height: 12),

                          // Live equity hero card
                          _EquityCard(
                            availableEquity: _availableEquity,
                            ltvPct: _ltvPct,
                            isEs: isEs,
                            fmt: _fmt,
                            fmtPct: _fmtPct,
                          ),

                          const SizedBox(height: 24),
                          Text(
                            isEs ? 'Detalles del HELOC' : 'HELOC Details',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: AppTextSize.bodyLg),
                          ),
                          const SizedBox(height: 16),

                          _buildField(
                            controller: _drawCtrl,
                            label: isEs
                                ? 'Monto a disponer (\$)'
                                : 'Draw Amount (\$)',
                            hint: '100000',
                            isCurrency: true,
                            validator: (v) {
                              final val = _parseNum(v ?? '');
                              if (val <= 0) {
                                return isEs
                                    ? 'Ingresa un monto'
                                    : 'Enter amount';
                              }
                              if (val > _availableEquity) {
                                return isEs
                                    ? 'Excede el capital disponible'
                                    : 'Exceeds available equity';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),

                          _buildField(
                            controller: _rateCtrl,
                            label: isEs ? 'Tasa HELOC (%)' : 'HELOC Rate (%)',
                            hint: '8.5',
                            validator: (v) => _parseNum(v ?? '') < 0
                                ? (isEs ? 'Tasa inválida' : 'Invalid rate')
                                : null,
                          ),
                          const SizedBox(height: 16),

                          Row(children: [
                            Expanded(
                              child: _buildField(
                                controller: _drawYearsCtrl,
                                label: isEs
                                    ? 'Período de disposición (años)'
                                    : 'Draw Period (years)',
                                hint: '10',
                                intOnly: true,
                                validator: (v) =>
                                    (int.tryParse(v ?? '') ?? 0) <= 0
                                        ? (isEs ? 'Inválido' : 'Invalid')
                                        : null,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: _buildField(
                                controller: _repayYearsCtrl,
                                label: isEs
                                    ? 'Período de pago (años)'
                                    : 'Repayment Period (years)',
                                hint: '20',
                                intOnly: true,
                                validator: (v) =>
                                    (int.tryParse(v ?? '') ?? 0) <= 0
                                        ? (isEs ? 'Inválido' : 'Invalid')
                                        : null,
                              ),
                            ),
                          ]),
                          const SizedBox(height: 24),

                          // ── IO vs P&I toggle ─────────────────────────────────────
                          _buildPaymentModeToggle(isEs),
                          const SizedBox(height: 16),

                          // ── More Tools — grouped expansion ─────────────────
                          Card(
                            margin: EdgeInsets.zero,
                            child: ExpansionTile(
                              leading: const Icon(Icons.build_rounded),
                              title: Text(
                                  isEs ? 'Más herramientas' : 'More tools'),
                              childrenPadding:
                                  const EdgeInsets.fromLTRB(16, 0, 16, 12),
                              children: [
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (_, __, ___) =>
                                          const DrawOptimizerScreen(),
                                      transitionsBuilder:
                                          (_, anim, __, child) =>
                                              FadeTransition(
                                                  opacity: anim, child: child),
                                      transitionDuration: AppDuration.base,
                                    ),
                                  ),
                                  icon: const Icon(
                                      Icons.account_balance_wallet_rounded,
                                      size: 18),
                                  label: Text(
                                      isEs
                                          ? 'Draw Optimizer'
                                          : 'Draw Optimizer',
                                      style: const TextStyle(
                                          fontSize: AppTextSize.md)),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.lg)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (_, __, ___) =>
                                          const PaymentShockScreen(),
                                      transitionsBuilder:
                                          (_, anim, __, child) =>
                                              FadeTransition(
                                                  opacity: anim, child: child),
                                      transitionDuration: AppDuration.base,
                                    ),
                                  ),
                                  icon:
                                      const Icon(Icons.bolt_rounded, size: 18),
                                  label: Text(
                                      isEs ? 'Choque de Pago' : 'Payment Shock',
                                      style: const TextStyle(
                                          fontSize: AppTextSize.md)),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.lg)),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    PageRouteBuilder(
                                      pageBuilder: (_, __, ___) =>
                                          const HelocVsCashoutScreen(),
                                      transitionsBuilder:
                                          (_, anim, __, child) =>
                                              FadeTransition(
                                                  opacity: anim, child: child),
                                      transitionDuration: AppDuration.base,
                                    ),
                                  ),
                                  icon: const Icon(Icons.swap_horiz_rounded,
                                      size: 18),
                                  label: Text(
                                      isEs
                                          ? 'HELOC vs Refi con Retiro'
                                          : 'HELOC vs Cash-Out Refi',
                                      style: const TextStyle(
                                          fontSize: AppTextSize.md)),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.lg)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton(
                            onPressed: _reset,
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(double.infinity, 52),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.xl)),
                            ),
                            child: Text(
                                isEs ? AppStringsES.reset : AppStringsEN.reset),
                          ),

                          // Results
                          AnimatedSwitcher(
                            duration: AppDuration.base,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.04),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              ),
                            ),
                            child: _results != null
                                ? KeyedSubtree(
                                    key: const ValueKey('results'),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 24),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  isEs
                                                      ? AppStringsES.results
                                                      : AppStringsEN.results,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      fontSize:
                                                          AppTextSize.subtitle),
                                                ),
                                              ),
                                              // Share button
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.share_rounded,
                                                    color: AppTheme.primary),
                                                tooltip: isEs
                                                    ? 'Compartir'
                                                    : 'Share',
                                                onPressed: () => _share(isEs),
                                              ),
                                              // PDF export button
                                              ValueListenableBuilder<bool>(
                                                valueListenable: freemiumService
                                                    .isPremiumNotifier,
                                                builder: (_, isPremium, __) =>
                                                    IconButton(
                                                  icon: Icon(
                                                    Icons
                                                        .picture_as_pdf_rounded,
                                                    color: isPremium
                                                        ? AppTheme.primary
                                                        : AppTheme.labelGray,
                                                  ),
                                                  tooltip: isPremium
                                                      ? (isEs
                                                          ? AppStringsES
                                                              .exportPdf
                                                          : AppStringsEN
                                                              .exportPdf)
                                                      : (isEs
                                                          ? AppStringsES
                                                              .exportLocked
                                                          : AppStringsEN
                                                              .exportLocked),
                                                  onPressed: () =>
                                                      _exportPdf(isEs),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),

                                          // ── Mode-aware primary payment card ──────────────────
                                          Builder(builder: (ctx) {
                                            final isIO = _paymentMode ==
                                                _PaymentMode.interestOnly;
                                            final drawPayment = isIO
                                                ? (_results!['interestOnly']
                                                        as double? ??
                                                    0)
                                                : (_results!['fullPI']
                                                        as double? ??
                                                    0);
                                            final totalInt = isIO
                                                ? (_results!['totalInterest']
                                                        as double? ??
                                                    0)
                                                : (_results![
                                                            'totalInterestFullPI']
                                                        as double? ??
                                                    0);
                                            final equity = _results!['equity']
                                                    as double? ??
                                                0;
                                            final drawYears =
                                                _results!['drawYears']
                                                        as int? ??
                                                    10;
                                            return CalcwiseHeroCard(
                                              label: isIO
                                                  ? (isEs
                                                      ? 'Pago Solo Interés'
                                                      : 'Interest-Only Payment')
                                                  : (isEs
                                                      ? 'Pago P&I'
                                                      : 'P&I Payment'),
                                              value:
                                                  '\$${_fmtDec.format(drawPayment)}',
                                              secondary: isIO
                                                  ? (isEs
                                                      ? '$drawYears años de disposición'
                                                      : '$drawYears-yr draw period')
                                                  : (isEs
                                                      ? 'P&I desde mes 1'
                                                      : 'P&I from month 1'),
                                              backgroundColor: AppTheme.primary,
                                              stats: [
                                                (
                                                  label: isEs
                                                      ? 'Interés total'
                                                      : 'Total Interest',
                                                  value: _fmt.format(totalInt)
                                                ),
                                                (
                                                  label: isEs
                                                      ? 'Capital disponible'
                                                      : 'Available Equity',
                                                  value: _fmt.format(equity)
                                                ),
                                              ],
                                            );
                                          }),
                                          const SizedBox(height: 8),
                                          Card(
                                            child: Padding(
                                              padding: const EdgeInsets.all(
                                                  AppSpacing.lg),
                                              child: Column(children: [
                                                MetricRow(
                                                  label: isEs
                                                      ? 'Capital disponible (85% LTV)'
                                                      : 'Available Equity (85% LTV)',
                                                  value: _fmt.format(
                                                      _results!['equity']),
                                                  valueColor: AppTheme.success,
                                                ),
                                                const Divider(height: 16),
                                                MetricRow(
                                                  label: isEs
                                                      ? 'Capacidad máx. préstamo (85%)'
                                                      : 'Max Borrow Capacity (85%)',
                                                  value: _fmt.format(
                                                      _results!['maxBorrow85']),
                                                  valueColor: AppTheme.primary,
                                                ),
                                                const Divider(height: 16),
                                                MetricRow(
                                                  label: isEs
                                                      ? 'LTV actual'
                                                      : 'Current LTV',
                                                  value:
                                                      '${_fmtPct.format(_results!['ltv'])}%',
                                                  valueColor: (_results!['ltv']
                                                              as double) >
                                                          85
                                                      ? AppTheme.error
                                                      : AppTheme.labelGray,
                                                ),
                                                Builder(builder: (ctx) {
                                                  final ltv = _results!['ltv']
                                                      as double;
                                                  final Color ltvTrafficColor;
                                                  final String ltvTrafficLabel;
                                                  if (ltv < 70) {
                                                    ltvTrafficColor =
                                                        CalcwiseTheme.of(ctx)
                                                            .successGreen;
                                                    ltvTrafficLabel = isEs
                                                        ? 'LTV conservador — excelente posición de crédito'
                                                        : 'Conservative LTV — excellent borrowing position';
                                                  } else if (ltv <= 80) {
                                                    ltvTrafficColor =
                                                        CalcwiseTheme.of(ctx)
                                                            .successGreen;
                                                    ltvTrafficLabel = isEs
                                                        ? 'LTV estándar — califica para las mejores tasas'
                                                        : 'Standard LTV — qualifies for best rates';
                                                  } else if (ltv <= 85) {
                                                    ltvTrafficColor =
                                                        CalcwiseTheme.of(ctx)
                                                            .warningOrange;
                                                    ltvTrafficLabel = isEs
                                                        ? 'LTV elevado — puede requerir PMI o tasas más altas'
                                                        : 'Elevated LTV — may require PMI or higher rates';
                                                  } else {
                                                    ltvTrafficColor =
                                                        CalcwiseTheme.of(ctx)
                                                            .errorRed;
                                                    ltvTrafficLabel = isEs
                                                        ? 'LTV alto — la mayoría de prestamistas no aprobarán el HELOC'
                                                        : 'High LTV — most lenders won\'t approve HELOC';
                                                  }
                                                  return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 4, bottom: 4),
                                                    child: Row(children: [
                                                      Container(
                                                        width: 10,
                                                        height: 10,
                                                        decoration:
                                                            BoxDecoration(
                                                          color:
                                                              ltvTrafficColor,
                                                          shape:
                                                              BoxShape.circle,
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Expanded(
                                                        child: Text(
                                                          ltvTrafficLabel,
                                                          style: TextStyle(
                                                            fontSize:
                                                                AppTextSize.xs,
                                                            color:
                                                                ltvTrafficColor,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                    ]),
                                                  );
                                                }),
                                                const Divider(height: 16),
                                                MetricRow(
                                                  label: _paymentMode ==
                                                          _PaymentMode
                                                              .interestOnly
                                                      ? (isEs
                                                          ? 'Interés total estimado'
                                                          : 'Total Interest (Estimated)')
                                                      : (isEs
                                                          ? 'Interés total (P&I completo)'
                                                          : 'Total Interest (Full P&I)'),
                                                  value: _fmt.format(
                                                    _paymentMode ==
                                                            _PaymentMode
                                                                .interestOnly
                                                        ? _results![
                                                            'totalInterest']
                                                        : _results![
                                                            'totalInterestFullPI'],
                                                  ),
                                                  valueColor:
                                                      AppTheme.errorDark,
                                                ),
                                              ]),
                                            ),
                                          ),
                                          // Tax savings + info banner
                                          ValueListenableBuilder<bool>(
                                            valueListenable: isSpanishNotifier,
                                            builder: (_, isSpanish, __) =>
                                                Container(
                                              margin: const EdgeInsets.only(
                                                  top: 12),
                                              padding: const EdgeInsets.all(
                                                  AppSpacing.md),
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppRadius.mdPlus),
                                                border: Border.all(
                                                    color:
                                                        AppTheme.infoBlueLight),
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                      Icons
                                                          .info_outline_rounded,
                                                      color: AppTheme.infoBlue,
                                                      size: 18),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        Text(
                                                          isSpanish
                                                              ? 'Los intereses del HELOC pueden ser deducibles de impuestos si se usan para mejoras del hogar. Consulta a un asesor fiscal.'
                                                              : 'HELOC interest may be tax-deductible if used for home improvements. Consult a tax advisor.',
                                                          style: TextStyle(
                                                              fontSize:
                                                                  AppTextSize
                                                                      .sm,
                                                              color: AppTheme
                                                                  .infoBlueDark,
                                                              height: 1.4),
                                                        ),
                                                        if ((_results?['taxSavings']
                                                                    as double? ??
                                                                0) >
                                                            0) ...[
                                                          const SizedBox(
                                                              height: 8),
                                                          Text(
                                                            isSpanish
                                                                ? 'Ahorro fiscal estimado (22%): ${_fmtDec.format(_results!['taxSavings'])}/año'
                                                                : 'Est. tax savings (22% bracket): ${_fmtDec.format(_results!['taxSavings'])}/year',
                                                            style: TextStyle(
                                                                fontSize:
                                                                    AppTextSize
                                                                        .sm,
                                                                color: AppTheme
                                                                    .infoBlueDark,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w600,
                                                                height: 1.4),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 24),
                                          // Smart Insights
                                          InsightCard(
                                            insights: InsightEngine.generate(
                                              homeValue: (_results!['homeValue']
                                                      as double? ??
                                                  0),
                                              mortgageBalance:
                                                  (_results!['mortgage']
                                                          as double? ??
                                                      0),
                                              helocLimit: (_results!['draw']
                                                      as double? ??
                                                  0),
                                              annualRatePct: (_results!['rate']
                                                      as double? ??
                                                  0),
                                              drawPayment:
                                                  (_results!['interestOnly']
                                                          as double? ??
                                                      0),
                                              repaymentPayment:
                                                  (_results!['repayment']
                                                          as double? ??
                                                      0),
                                              totalInterest:
                                                  (_results!['totalInterest']
                                                          as double? ??
                                                      0),
                                              isEs: isEs,
                                            ),
                                            isSpanish: isEs,
                                          ),
                                          const SizedBox(height: 24),
                                          _buildRateScenarios(isEs),
                                          const SizedBox(height: 24),
                                          // Feature 3 — Interest-Only vs Fully Amortizing
                                          _IoVsFullyAmortizingCard(
                                            draw: (_results!['draw']
                                                    as double?) ??
                                                0,
                                            rate: (_results!['rate']
                                                    as double?) ??
                                                0,
                                            drawYears: (_results!['drawYears']
                                                    as int?) ??
                                                10,
                                            repayYears: (_results!['repayYears']
                                                    as int?) ??
                                                20,
                                            isEs: isEs,
                                          ),
                                          const SizedBox(height: 24),
                                          // Feature 1 — Rate Sensitivity sliders
                                          ValueListenableBuilder<bool>(
                                            valueListenable: freemiumService
                                                .isPremiumNotifier,
                                            builder: (_, isPremium, __) {
                                              if (!isPremium) {
                                                return PremiumCtaWidget(
                                                  feature: isEs
                                                      ? 'Sensibilidad de Tasa'
                                                      : 'Rate Sensitivity',
                                                );
                                              }
                                              return _RateSensitivityWidget(
                                                draw: (_results!['draw']
                                                        as double?) ??
                                                    0,
                                                baseRate: (_results!['rate']
                                                        as double?) ??
                                                    0,
                                                drawYears:
                                                    (_results!['drawYears']
                                                            as int?) ??
                                                        10,
                                                repayYears:
                                                    (_results!['repayYears']
                                                            as int?) ??
                                                        20,
                                                isEs: isEs,
                                              );
                                            },
                                          ),
                                        ]))
                                : Padding(
                                    key: const ValueKey('heloc_empty'),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 32),
                                    child: Column(children: [
                                      Icon(Icons.account_balance_rounded,
                                          size: 48,
                                          color: CalcwiseTheme.of(context)
                                              .textSecondary
                                              .withValues(alpha: 0.4)),
                                      const SizedBox(height: 12),
                                      Text(
                                          'Enter property details to calculate',
                                          style: TextStyle(
                                              color: CalcwiseTheme.of(context)
                                                  .textSecondary,
                                              fontSize: AppTextSize.body)),
                                    ]),
                                  ),
                          ),

                          // Save button + Compare Options — shown when results are available
                          if (_results != null) ...[
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _saveToHistory,
                              icon: const Icon(Icons.bookmark_add_rounded),
                              label: Text(isEs
                                  ? 'Guardar en Historial'
                                  : 'Save to History'),
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 52),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xl)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () {
                                // Switch to the Compare tab (index 2)
                                DefaultTabController.maybeOf(context);
                                // Navigate directly via named ancestor state if accessible,
                                // otherwise use a simple Navigator push to CompareScreen.
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (_, __, ___) => Scaffold(
                                      appBar: AppBar(
                                        title: Text(isEs
                                            ? 'Comparar Opciones'
                                            : 'Compare Options'),
                                      ),
                                      body: const CompareScreen(),
                                    ),
                                    transitionsBuilder: (_, anim, __, child) =>
                                        FadeTransition(
                                            opacity: anim, child: child),
                                    transitionDuration: AppDuration.base,
                                  ),
                                );
                              },
                              icon: const Icon(Icons.compare_arrows_rounded,
                                  size: 18),
                              label: Text(isEs
                                  ? 'Comparar Opciones de Financiamiento'
                                  : 'Compare Financing Options'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                foregroundColor: AppTheme.primary,
                                side: const BorderSide(color: AppTheme.primary),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xl)),
                              ),
                            ),
                          ],

                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ), // CalcwisePageEntrance closes
                ),
              ),
            ),
          ),
          const CalcwiseAdFooter(),
        ],
      ),
    );
  }

  Widget _buildPaymentModeToggle(bool isEs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEs
              ? 'Modo de pago durante disposición'
              : 'Draw Period Payment Mode',
          style: const TextStyle(
              fontWeight: FontWeight.w600, fontSize: AppTextSize.body),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_PaymentMode>(
          segments: [
            ButtonSegment<_PaymentMode>(
              value: _PaymentMode.interestOnly,
              label: Text(isEs ? 'Solo Interés' : 'Interest-Only',
                  style: const TextStyle(fontSize: AppTextSize.sm)),
              icon: const Icon(Icons.payments_rounded, size: 16),
            ),
            ButtonSegment<_PaymentMode>(
              value: _PaymentMode.fullPI,
              label: Text(isEs ? 'P&I Completo' : 'Full P&I',
                  style: const TextStyle(fontSize: AppTextSize.sm)),
              icon: const Icon(Icons.account_balance_rounded, size: 16),
            ),
          ],
          selected: {_paymentMode},
          onSelectionChanged: (sel) {
            setState(() {
              _paymentMode = sel.first;
            });
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
            shape: WidgetStateProperty.all(
              RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _paymentMode == _PaymentMode.interestOnly
              ? (isEs
                  ? 'Durante el período de disposición solo pagas intereses. El saldo completo se amortiza después.'
                  : 'During the draw period you pay interest only. The full balance amortizes after.')
              : (isEs
                  ? 'El pago amortiza capital e interés desde el primer mes sobre el término completo.'
                  : 'Payment amortizes both principal & interest from month 1 over the full term.'),
          style: const TextStyle(
              fontSize: AppTextSize.xs, color: AppTheme.labelGray, height: 1.4),
        ),
      ],
    );
  }

  Widget _buildRateScenarios(bool isEs) {
    if (_results == null || _cachedScenarios == null)
      return const SizedBox.shrink();
    final baseRate = (_results!['rate'] as double?) ?? 0;
    if (baseRate <= 0) return const SizedBox.shrink();

    final title = isEs ? 'Escenarios de Tasa' : 'Rate Scenarios';
    final fmtShort =
        NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.compare_arrows,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            // Header row
            Row(children: [
              Expanded(
                flex: 2,
                child: Text(isEs ? 'Tasa' : 'Rate',
                    style: const TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
              Expanded(
                flex: 3,
                child: Text(isEs ? 'Interés' : 'Draw Pmt',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
              Expanded(
                flex: 3,
                child: Text(isEs ? 'Amortizado' : 'Repay Pmt',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
              Expanded(
                flex: 3,
                child: Text(isEs ? 'Int. Total' : 'Total Int.',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
            ]),
            const SizedBox(height: 8),
            ..._cachedScenarios!.map((scenario) {
              final offset = scenario['offset'] as int;
              final scenarioRate = scenario['scenarioRate'] as double;
              final drawPmt = scenario['drawPmt'] as double;
              final repayPmt = scenario['repayPmt'] as double;
              final totalInt = scenario['totalInt'] as double;
              final isCurrent = offset == 0;
              final isBelow = offset < 0;
              final textColor = isCurrent
                  ? AppTheme.primary
                  : isBelow
                      ? AppTheme.successDark
                      : AppTheme.errorDark;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                decoration: isCurrent
                    ? BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      )
                    : null,
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${scenarioRate.toStringAsFixed(1)}%${isCurrent ? " ✦" : ""}',
                      style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtShort.format(drawPmt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.normal,
                          color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtShort.format(repayPmt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.normal,
                          color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtShort.format(totalInt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: AppTextSize.sm,
                          fontWeight:
                              isCurrent ? FontWeight.w700 : FontWeight.normal,
                          color: textColor),
                    ),
                  ),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    bool intOnly = false,
    bool isCurrency = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: intOnly
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: isCurrency
          ? [CurrencyInputFormatter(locale: 'en_US')]
          : [
              FilteringTextInputFormatter.allow(
                  intOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]')),
            ],
      decoration: InputDecoration(labelText: label, hintText: hint),
      validator: validator,
    );
  }
}

class _EquityCard extends StatelessWidget {
  final double availableEquity;
  final double ltvPct;
  final bool isEs;
  final NumberFormat fmt;
  final NumberFormat fmtPct;

  const _EquityCard({
    required this.availableEquity,
    required this.ltvPct,
    required this.isEs,
    required this.fmt,
    required this.fmtPct,
  });

  @override
  Widget build(BuildContext context) {
    final isOverLtv = ltvPct > 85;
    final equityColor = availableEquity > 0
        ? AppTheme.success
        : CalcwiseTheme.of(context).warningOrange;
    final ltvColor = isOverLtv ? AppTheme.error : AppTheme.success;
    final ltvFraction = (ltvPct / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.08),
            AppTheme.primary.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_rounded,
                color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              isEs
                  ? 'Tu capital disponible (85% LTV)'
                  : 'Your available equity (85% LTV)',
              style: TextStyle(
                  fontSize: AppTextSize.sm,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primary.withValues(alpha: 0.85)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            isEs
                ? 'Máx. disponible (85%): ${fmt.format(availableEquity)}'
                : 'Max available (85% LTV): ${fmt.format(availableEquity)}',
            style: TextStyle(
              fontSize: AppTextSize.title,
              fontWeight: FontWeight.w800,
              color: equityColor,
            ),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: ClipRoundedRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(
                  value: ltvFraction,
                  minHeight: 7,
                  backgroundColor: const Color(0xFFE2E8F0),
                  valueColor: AlwaysStoppedAnimation<Color>(ltvColor),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'LTV ${fmtPct.format(ltvPct)}%',
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: FontWeight.w700,
                color: ltvColor,
              ),
            ),
          ]),
          if (isOverLtv) ...[
            const SizedBox(height: 8),
            Text(
              isEs
                  ? '⚠ LTV superior al 85% — sin capital HELOC disponible'
                  : '⚠ LTV above 85% — no HELOC equity available',
              style: const TextStyle(
                  fontSize: AppTextSize.xs, color: AppTheme.error),
            ),
          ],
        ],
      ),
    );
  }
}

// Flutter doesn't have a built-in ClipRoundedRect — use ClipRRect
class ClipRoundedRect extends StatelessWidget {
  final BorderRadius borderRadius;
  final Widget child;
  const ClipRoundedRect({required this.borderRadius, required this.child});

  @override
  Widget build(BuildContext context) =>
      ClipRRect(borderRadius: borderRadius, child: child);
}

// ============================================================================
// Feature 1 — Rate Sensitivity Widget (Premium)
// ============================================================================

class _RateSensitivityWidget extends StatefulWidget {
  final double draw;
  final double baseRate;
  final int drawYears;
  final int repayYears;
  final bool isEs;

  const _RateSensitivityWidget({
    required this.draw,
    required this.baseRate,
    required this.drawYears,
    required this.repayYears,
    required this.isEs,
  });

  @override
  State<_RateSensitivityWidget> createState() => _RateSensitivityWidgetState();
}

class _RateSensitivityWidgetState extends State<_RateSensitivityWidget> {
  double _delta = 0.0; // -3.0 .. +3.0 in 0.25 steps

  final _fmt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtInt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

  double get _scenarioRate => (widget.baseRate + _delta).clamp(0.01, 50.0);

  double get _baseMonthly =>
      HelocEngine.interestOnlyPayment(widget.draw, widget.baseRate);

  double get _newMonthly =>
      HelocEngine.interestOnlyPayment(widget.draw, _scenarioRate);

  double get _baseTotal => HelocEngine.totalInterestPaid(
      widget.draw, widget.baseRate, widget.drawYears, widget.repayYears);

  double get _newTotal => HelocEngine.totalInterestPaid(
      widget.draw, _scenarioRate, widget.drawYears, widget.repayYears);

  void _applyQuick(double offset) {
    setState(() => _delta = offset.clamp(-3.0, 3.0));
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    final paymentDelta = _newMonthly - _baseMonthly;
    final totalDelta = _newTotal - _baseTotal;
    final isUp = _delta > 0;
    final isDown = _delta < 0;
    final arrowColor = isUp
        ? AppTheme.errorDark
        : isDown
            ? AppTheme.successDark
            : AppTheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(children: [
              const Icon(Icons.tune, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                isEs ? 'Sensibilidad de Tasa' : 'Rate Sensitivity',
                style: const TextStyle(
                    fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 12),
                  const SizedBox(width: 3),
                  Text('Premium',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.amber.shade800,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              isEs
                  ? '¿Qué pasaría si tu tasa cambia?'
                  : 'What if your rate goes up or down?',
              style: const TextStyle(
                  fontSize: AppTextSize.sm, color: AppTheme.labelGray),
            ),
            const SizedBox(height: 16),

            // Quick chips
            Row(children: [
              _QuickChip(
                label: isEs ? 'Tasa +1%' : 'Rate +1%',
                onTap: () => _applyQuick(1.0),
                isSelected: _delta == 1.0,
                color: AppTheme.errorDark,
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: isEs ? 'Tasa +2%' : 'Rate +2%',
                onTap: () => _applyQuick(2.0),
                isSelected: _delta == 2.0,
                color: AppTheme.errorDark,
              ),
              const SizedBox(width: 8),
              _QuickChip(
                label: isEs ? 'Restablecer' : 'Reset',
                onTap: () => _applyQuick(0.0),
                isSelected: _delta == 0.0,
                color: AppTheme.primary,
              ),
            ]),

            const SizedBox(height: 16),

            // Slider
            Row(children: [
              const Text('-3%',
                  style: TextStyle(
                      fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
              Expanded(
                child: Slider(
                  value: _delta,
                  min: -3.0,
                  max: 3.0,
                  divisions: 24, // 0.25 step
                  activeColor: arrowColor,
                  label: _delta >= 0
                      ? '+${_delta.toStringAsFixed(2)}%'
                      : '${_delta.toStringAsFixed(2)}%',
                  onChanged: (v) =>
                      setState(() => _delta = (v * 4).round() / 4),
                ),
              ),
              const Text('+3%',
                  style: TextStyle(
                      fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
            ]),

            // Scenario label
            Center(
              child: Text(
                _delta == 0
                    ? (isEs
                        ? 'Tasa actual: ${widget.baseRate.toStringAsFixed(2)}%'
                        : 'Current rate: ${widget.baseRate.toStringAsFixed(2)}%')
                    : (isEs
                        ? 'Si la tasa ${isUp ? "sube" : "baja"} ${_delta.abs().toStringAsFixed(2)}% → ${_scenarioRate.toStringAsFixed(2)}%'
                        : 'If rate ${isUp ? "rises" : "drops"} ${_delta.abs().toStringAsFixed(2)}% → ${_scenarioRate.toStringAsFixed(2)}%'),
                style: TextStyle(
                  fontSize: AppTextSize.md,
                  fontWeight: FontWeight.w600,
                  color: arrowColor,
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Result cards
            if (_delta != 0) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: arrowColor.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: arrowColor.withValues(alpha: 0.2)),
                ),
                child: Column(children: [
                  _SensRow(
                    label: isEs
                        ? 'Nuevo pago mensual (interés)'
                        : 'New monthly payment (interest)',
                    value: _fmt.format(_newMonthly),
                    delta: paymentDelta,
                    color: arrowColor,
                    isEs: isEs,
                  ),
                  const Divider(height: 16),
                  _SensRow(
                    label:
                        isEs ? 'Delta interés total' : 'Total interest delta',
                    value: _fmtInt.format(_newTotal),
                    delta: totalDelta,
                    color: arrowColor,
                    isEs: isEs,
                  ),
                ]),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Center(
                  child: Text(
                    isEs
                        ? 'Mueve el slider para ver el impacto en tiempo real.'
                        : 'Move the slider to see real-time impact.',
                    style: const TextStyle(
                        fontSize: AppTextSize.sm, color: AppTheme.labelGray),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool isSelected;
  final Color color;

  const _QuickChip({
    required this.label,
    required this.onTap,
    required this.isSelected,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:
              isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? color : CalcwiseTheme.of(context).cardBorder,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: AppTextSize.sm,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? color : AppTheme.labelGray,
          ),
        ),
      ),
    );
  }
}

class _SensRow extends StatelessWidget {
  final String label;
  final String value;
  final double delta;
  final Color color;
  final bool isEs;

  const _SensRow({
    required this.label,
    required this.value,
    required this.delta,
    required this.color,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    final sign = delta >= 0 ? '+' : '';
    final fmtDelta =
        NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label,
              style: const TextStyle(
                  fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: AppTextSize.bodyMd,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ]),
      ),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(
          isEs ? 'Cambio' : 'Change',
          style: const TextStyle(fontSize: 10, color: AppTheme.labelGray),
        ),
        Text(
          '$sign${fmtDelta.format(delta)}',
          style: TextStyle(
            fontSize: AppTextSize.md,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ]),
    ]);
  }
}

// ============================================================================
// Feature 3 — Interest-Only vs Fully Amortizing Comparison
// ============================================================================

class _IoVsFullyAmortizingCard extends StatelessWidget {
  final double draw;
  final double rate;
  final int drawYears;
  final int repayYears;
  final bool isEs;

  const _IoVsFullyAmortizingCard({
    required this.draw,
    required this.rate,
    required this.drawYears,
    required this.repayYears,
    required this.isEs,
  });

  @override
  Widget build(BuildContext context) {
    if (draw <= 0 || rate <= 0) return const SizedBox.shrink();

    final r = rate / 100 / 12;

    // ── Interest-Only path ───────────────────────────────────────────────────
    final ioDrawPayment = HelocEngine.interestOnlyPayment(draw, rate);
    final ioRepayPayment = HelocEngine.amortizedPayment(draw, rate, repayYears);
    final ioTotalInterest =
        HelocEngine.totalInterestPaid(draw, rate, drawYears, repayYears);
    final ioTotalPaid = ioTotalInterest + draw;

    // ── Fully Amortizing from Day 1 ──────────────────────────────────────────
    // Total term = drawYears + repayYears; amortize over full term from month 1
    final fullTermMonths = (drawYears + repayYears) * 12;
    final faMonthly = draw *
        r *
        pow(1 + r, fullTermMonths) /
        (pow(1 + r, fullTermMonths) - 1);
    final faTotalPaid = faMonthly * fullTermMonths;
    final faTotalInterest = faTotalPaid - draw;

    // ── Verdict ──────────────────────────────────────────────────────────────
    final monthlyDraw =
        ioDrawPayment - faMonthly; // +ve means IO cheaper during draw
    final totalDiff = faTotalInterest -
        ioTotalInterest; // +ve means FA costs more overall... actually IO costs more

    // IO: lower monthly during draw but higher total; FA: higher monthly but lower total
    final fmt =
        NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
    final fmtInt =
        NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(children: [
              const Icon(Icons.compare, color: AppTheme.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEs
                      ? 'Solo Interés vs Amortización Completa'
                      : 'Interest-Only vs Fully Amortizing',
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 16),

            // Column headers
            Row(children: [
              const SizedBox(width: 120),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.09),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      bottomLeft: Radius.circular(8),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isEs ? 'Solo Interés' : 'Interest-Only',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                          fontSize: AppTextSize.sm),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF01579B).withValues(alpha: 0.09),
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isEs ? 'Amort. Completa' : 'Fully Amortizing',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF01579B),
                          fontSize: AppTextSize.sm),
                    ),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 8),

            // Row: monthly payment draw phase
            _CompRow(
              label: isEs
                  ? 'Pago mensual\n(fase disposición)'
                  : 'Monthly payment\n(draw phase)',
              val1: fmt.format(ioDrawPayment),
              val2: fmt.format(faMonthly),
              winner: ioDrawPayment < faMonthly ? 0 : 1,
            ),
            _CompRow(
              label: isEs
                  ? 'Pago mensual\n(fase de pago)'
                  : 'Monthly payment\n(repay phase)',
              val1: fmt.format(ioRepayPayment),
              val2: fmt.format(faMonthly),
              winner: ioRepayPayment < faMonthly ? 0 : 1,
            ),
            _CompRow(
              label: isEs ? 'Interés total' : 'Total interest',
              val1: fmtInt.format(ioTotalInterest),
              val2: fmtInt.format(faTotalInterest),
              highlight: true,
              winner: ioTotalInterest < faTotalInterest ? 0 : 1,
            ),
            _CompRow(
              label: isEs ? 'Total pagado' : 'Total paid',
              val1: fmtInt.format(ioTotalPaid),
              val2: fmtInt.format(faTotalPaid),
              winner: ioTotalPaid < faTotalPaid ? 0 : 1,
            ),

            const SizedBox(height: 16),

            // Verdict badge
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(children: [
                Icon(Icons.lightbulb_outline,
                    color: Colors.amber.shade700, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEs
                        ? 'Solo interés ahorra ${fmt.format(monthlyDraw.abs())}/mes ahora, '
                            'pero cuesta ${fmtInt.format(totalDiff.abs())} ${totalDiff > 0 ? "más" : "menos"} en total.'
                        : 'Interest-only saves ${fmt.format(monthlyDraw.abs())}/mo now, '
                            'costs ${fmtInt.format(totalDiff.abs())} ${totalDiff > 0 ? "more" : "less"} total.',
                    style: TextStyle(
                        fontSize: AppTextSize.sm,
                        color: Colors.amber.shade900,
                        height: 1.4),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompRow extends StatelessWidget {
  final String label;
  final String val1;
  final String val2;
  final bool highlight;
  final int winner; // 0 = left wins, 1 = right wins, -1 = tie

  const _CompRow({
    required this.label,
    required this.val1,
    required this.val2,
    this.highlight = false,
    this.winner = -1,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTextSize.xs,
              color: AppTheme.labelGray,
              fontWeight: highlight ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        Expanded(child: _Cell(val1, winner == 0, highlight, AppTheme.primary)),
        const SizedBox(width: 4),
        Expanded(
            child:
                _Cell(val2, winner == 1, highlight, const Color(0xFF01579B))),
      ]),
    );
  }
}

class _Cell extends StatelessWidget {
  final String value;
  final bool isWinner;
  final bool highlight;
  final Color winColor;

  const _Cell(this.value, this.isWinner, this.highlight, this.winColor);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: isWinner ? winColor.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: isWinner
            ? Border.all(color: winColor.withValues(alpha: 0.25))
            : null,
      ),
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: highlight ? 14 : 12,
          fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
          color: isWinner ? winColor : null,
        ),
      ),
    );
  }
}
