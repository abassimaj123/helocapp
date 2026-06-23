import 'dart:async' show unawaited;
import 'dart:isolate';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share;

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
import '../widgets/save_scenario_button.dart';
import '../core/freemium/iap_service.dart';
import '../widgets/result_card.dart';
import '../core/insight_engine.dart';
import 'compare_screen.dart';
import 'draw_optimizer_screen.dart';
import 'heloc_vs_cashout_screen.dart';
import 'payment_shock_screen.dart';
import 'history_screen.dart';

const _chartAmberColor = Color(0xFFF9A825);
const _helocScenarioColor = Color(0xFF01579B);

// -- PDF params (only sendable primitives) ------------------------------------

class _CalculatorPdfParams {
  final double homeValue;
  final double mortgage;
  final double draw;
  final double rate;
  final int drawYears;
  final int repayYears;
  final double equity;
  final double ltv;
  final double interestOnly;
  final double repayment;
  final double taxSavings;
  final bool isEs;
  final bool isFr;
  final int nowMs;
  const _CalculatorPdfParams({
    required this.homeValue,
    required this.mortgage,
    required this.draw,
    required this.rate,
    required this.drawYears,
    required this.repayYears,
    required this.equity,
    required this.ltv,
    required this.interestOnly,
    required this.repayment,
    required this.taxSavings,
    required this.isEs,
    required this.isFr,
    required this.nowMs,
  });
}

// -- Top-level PDF builder (runs in Isolate) ----------------------------------

pw.Widget _calcPdfSectionTitle(String title) {
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

pw.Widget _calcPdfTable(List<List<String>> rows, {bool highlightFirst = false}) {
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
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: pw.Text(e.value[0],
                style: const pw.TextStyle(
                    fontSize: 10, color: PdfColors.grey700)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

Future<Uint8List> _buildCalculatorPdf(_CalculatorPdfParams p) async {
  final fmtPct = NumberFormat('##0.0#');
  final dateFmt = DateFormat('MMM d, yyyy');
  final now = DateTime.fromMillisecondsSinceEpoch(p.nowMs);

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
            _calcPdfSectionTitle(p.isEs ? 'Datos de Entrada' : 'Input Parameters'),
            pw.SizedBox(height: 8),
            _calcPdfTable(
              p.isEs
                  ? [
                      ['Valor de la vivienda', AmountFormatter.ui(p.homeValue, 'USD')],
                      ['Saldo hipotecario', AmountFormatter.ui(p.mortgage, 'USD')],
                      ['Monto a disponer', AmountFormatter.ui(p.draw, 'USD')],
                      ['Tasa HELOC', '${p.rate.toStringAsFixed(2)}%'],
                      ['Periodo de disposicion', '${p.drawYears} años'],
                      ['Periodo de pago', '${p.repayYears} años'],
                    ]
                  : [
                      ['Home Value', AmountFormatter.ui(p.homeValue, 'USD')],
                      ['Mortgage Balance', AmountFormatter.ui(p.mortgage, 'USD')],
                      ['Draw Amount', AmountFormatter.ui(p.draw, 'USD')],
                      ['HELOC Rate', '${p.rate.toStringAsFixed(2)}%'],
                      ['Draw Period', '${p.drawYears} years'],
                      ['Repayment Period', '${p.repayYears} years'],
                    ],
            ),
            pw.SizedBox(height: 20),

            // Results
            _calcPdfSectionTitle(p.isEs ? 'Resultados' : 'Results'),
            pw.SizedBox(height: 8),
            _calcPdfTable(
              p.isEs
                  ? [
                      [
                        'Pago solo interes (periodo disposicion)',
                        AmountFormatter.ui(p.interestOnly, 'USD')
                      ],
                      [
                        'Pago amortizado (periodo de pago)',
                        AmountFormatter.ui(p.repayment, 'USD')
                      ],
                      ['Capital disponible (85% LTV)', AmountFormatter.ui(p.equity, 'USD')],
                      ['LTV actual', '${fmtPct.format(p.ltv)}%'],
                      [
                        'Ahorro fiscal estimado (22%)',
                        '${AmountFormatter.ui(p.taxSavings, "USD")}/año'
                      ],
                    ]
                  : [
                      [
                        'Interest-Only Payment (Draw Period)',
                        AmountFormatter.ui(p.interestOnly, 'USD')
                      ],
                      [
                        'Repayment Payment (After Draw)',
                        AmountFormatter.ui(p.repayment, 'USD')
                      ],
                      ['Available Equity (85% LTV)', AmountFormatter.ui(p.equity, 'USD')],
                      ['Current LTV', '${fmtPct.format(p.ltv)}%'],
                      [
                        'Est. Tax Savings (22% bracket)',
                        '${AmountFormatter.ui(p.taxSavings, "USD")}/year'
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
                    p.isEs
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
                    p.isEs
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
              p.isEs
                  ? 'Aviso legal: Este informe es solo para fines informativos y no constituye asesoramiento financiero, fiscal ni legal. Los resultados son estimaciones y pueden variar. Consulte a profesionales calificados antes de tomar decisiones financieras.'
                  : 'Disclaimer: This report is for informational purposes only and does not constitute financial, tax, or legal advice. Results are estimates and may vary. Consult qualified professionals before making financial decisions.',
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        );
      },
    ),
  );
  return doc.save();
}

class CalculatorScreen extends StatefulWidget {
  const CalculatorScreen({super.key});

  @override
  State<CalculatorScreen> createState() => _CalculatorScreenState();
}

double _parseNum(String v) {
  if (v.isEmpty) return 0.0;
  String s;
  if (v.contains('.') && v.contains(',')) {
    s = v.lastIndexOf('.') > v.lastIndexOf(',')
        ? v.replaceAll(',', '')
        : v.replaceAll('.', '').replaceAll(',', '.');
  } else if (v.contains(',')) {
    final parts = v.split(',');
    s = parts.sublist(1).every((p) => p.length == 3)
        ? v.replaceAll(',', '')
        : v.replaceAll(',', '.');
  } else {
    s = v;
  }
  return double.tryParse(s.trim()) ?? 0.0;
}

/// Payment mode selected by the IO vs P&I toggle.
enum _PaymentMode { interestOnly, fullPI }

class _CalculatorScreenState extends State<CalculatorScreen> with CalcwiseAutoCalcMixin {
  final _formKey = GlobalKey<FormState>();

  final _homeValueCtrl = TextEditingController(text: '400000');
  final _mortgageCtrl = TextEditingController(text: '250000');
  final _drawCtrl = TextEditingController(text: '100000');
  final _rateCtrl = TextEditingController(text: '7.5');
  final _taxBracketCtrl = TextEditingController(text: '22');
  final _drawYearsCtrl = TextEditingController(text: '10');
  final _repayYearsCtrl = TextEditingController(text: '20');

  final _fmtPct = NumberFormat('##0.0#');

  double _taxBracket = 22.0;

  // Live computed equity
  double _availableEquity = 200000;

  // IO vs P&I toggle
  _PaymentMode _paymentMode = _PaymentMode.interestOnly;

  Map<String, dynamic>? _results;
  List<Map<String, dynamic>>? _cachedScenarios;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('calculator');
    _homeValueCtrl.addListener(_updateEquity);
    _mortgageCtrl.addListener(_updateEquity);
    for (final c in [
      _homeValueCtrl,
      _mortgageCtrl,
      _drawCtrl,
      _rateCtrl,
      _taxBracketCtrl,
      _drawYearsCtrl,
      _repayYearsCtrl
    ]) {
      c.addListener(() => scheduleCalc(_tryCalculate));
    }
    _taxBracketCtrl.addListener(() {
      _taxBracket = (double.tryParse(_taxBracketCtrl.text) ?? 22.0).clamp(0.0, 50.0);
    });
    _updateEquity();
    isSpanishNotifier.addListener(_onLangChange);
    // Run initial calculation with default values
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCalculate());
  }

  void _onLangChange() => setState(() {});

  void _updateEquity() {
    final homeValue = _parseNum(_homeValueCtrl.text);
    final mortgage = _parseNum(_mortgageCtrl.text);
    final equity = HelocEngine.availableEquity(homeValue, mortgage);
    final ltv = HelocEngine.ltv(mortgage, homeValue);
    if (mounted)
      setState(() {
        _availableEquity = equity;
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
    final taxSavings = HelocEngine.estimatedAnnualTaxSavings(draw, rate, _taxBracket);
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
    // Update global notifier so secondary tools can pre-fill from latest values.
    helocNotifier.value = (creditLimit: draw, balance: draw, rate: rate);

    // Auto-save: debounced ring-buffer via SmartHistory.
    final inputs = _resultsToInputs();
    final results = _resultsToResults();
    smartHistoryService.scheduleAutoSave(
      appKey: 'helocapp',
      screenId: 'calculator',
      inputHash: _resultHash(inputs),
      l1: _buildL1(inputs, results),
      l2: {'inputs': inputs, 'results': results},
      onSaved: () {
        if (mounted) {
          setState(() {});
          HistoryScreen.refreshNotifier.value++;
        }
      },
    );
  }

  // ── SmartHistory payload helpers ───────────────────────────────────────────

  Map<String, dynamic> _resultsToInputs() => {
        'homeValue': (_results!['homeValue'] as double?) ?? 0,
        'balance': (_results!['mortgage'] as double?) ?? 0,
        'draw': (_results!['draw'] as double?) ?? 0,
        'rate': (_results!['rate'] as double?) ?? 0,
        'drawYears': (_results!['drawYears'] as int?) ?? 10,
        'repayYears': (_results!['repayYears'] as int?) ?? 20,
      };

  Map<String, dynamic> _resultsToResults() => {
        'equity': (_results!['equity'] as double?) ?? 0,
        'ltv': (_results!['ltv'] as double?) ?? 0,
        'interestOnly': (_results!['interestOnly'] as double?) ?? 0,
        'repayment': (_results!['repayment'] as double?) ?? 0,
        'totalInterest': (_results!['totalInterest'] as double?) ?? 0,
        'taxSavings': (_results!['taxSavings'] as double?) ?? 0,
      };

  String _resultHash(Map<String, dynamic> inputs) => ResultHasher.hashMixed({
        'home': ResultHasher.roundTo(
            (inputs['homeValue'] as num).toDouble(), 1000),
        'bal':
            ResultHasher.roundTo((inputs['balance'] as num).toDouble(), 1000),
        'draw':
            ResultHasher.roundTo((inputs['draw'] as num).toDouble(), 1000),
        'rate':
            ResultHasher.roundTo((inputs['rate'] as num).toDouble(), 0.01),
        'dyrs': inputs['drawYears'],
        'ryrs': inputs['repayYears'],
      });

  Map<String, dynamic> _buildL1(
          Map<String, dynamic> inputs, Map<String, dynamic> results) =>
      {
        'draw_amount': (inputs['draw'] as num).toDouble(),
        'rate': (inputs['rate'] as num).toDouble(),
        'interest_only': (results['interestOnly'] as num).toDouble(),
        'monthly_payment': (results['repayment'] as num).toDouble(),
        'total_interest': (results['totalInterest'] as num).toDouble(),
      };

  /// Computes rate scenario rows without touching the widget tree.
  List<Map<String, dynamic>> _computeScenarioData({
    required double draw,
    required double baseRate,
    required int drawYears,
    required int repayYears,
  }) {
    const offsets = [-1, 0, 1, 2];
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
    isSpanishNotifier.removeListener(_onLangChange);
    smartHistoryService.cancelPendingSave('helocapp', 'calculator');
    _homeValueCtrl.removeListener(_updateEquity);
    _mortgageCtrl.removeListener(_updateEquity);
    _homeValueCtrl.dispose();
    _mortgageCtrl.dispose();
    _drawCtrl.dispose();
    _rateCtrl.dispose();
    _taxBracketCtrl.dispose();
    _drawYearsCtrl.dispose();
    _repayYearsCtrl.dispose();
    super.dispose();
  }

  Future<void> _calculate() async {
    smartHistoryService.cancelPendingSave('helocapp', 'calculator');
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
    final taxSavings = HelocEngine.estimatedAnnualTaxSavings(draw, rate, _taxBracket);
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
    unawaited(AnalyticsService.instance.maybeLogFirstCalculate());
    adService.onAction();
    HapticFeedback.mediumImpact();

    final trigger = await paywallSession.recordAction();
    if (trigger != PaywallTrigger.none &&
        mounted &&
        !freemiumService.hasFullAccess) {
      if (trigger == PaywallTrigger.soft) {
        AnalyticsService.instance.logPaywallSoftShown();
        PaywallSoft.show(context);
      } else {
        AnalyticsService.instance.logPaywallHardShown();
        PaywallHard.show(context);
      }
    }

    // Immediate auto-save into the ring buffer (bypass debounce).
    final inputs = _resultsToInputs();
    final results = _resultsToResults();
    smartHistoryService.scheduleAutoSave(
      appKey: 'helocapp',
      screenId: 'calculator',
      inputHash: _resultHash(inputs),
      l1: _buildL1(inputs, results),
      l2: {'inputs': inputs, 'results': results},
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
  }

  /// Pin the current result as a saved scenario via SmartHistory.
  Future<void> _saveScenario(String? label) async {
    if (_results == null) return;
    final inputs = _resultsToInputs();
    final results = _resultsToResults();
    HapticFeedback.mediumImpact();
    await smartHistoryService.saveScenario(
      appKey: 'helocapp',
      screenId: 'calculator',
      inputHash: _resultHash(inputs),
      l1: _buildL1(inputs, results),
      l2: {'inputs': inputs, 'results': results},
      label: label,
    );
    adService.onSave();
  }

  void _reset() {
    _homeValueCtrl.text = '400000';
    _mortgageCtrl.text = '250000';
    _drawCtrl.text = '100000';
    _rateCtrl.text = '7.5';
    _taxBracketCtrl.text = '22';
    _taxBracket = 22.0;
    _drawYearsCtrl.text = '10';
    _repayYearsCtrl.text = '20';
    setState(() => _results = null);
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  Future<void> _share(bool isEs, {bool isFr = false}) async {
    if (_results == null) return;

    final text = _buildShareText(isEs, isFr: isFr);
    try {
      await Share.share(text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFr
                ? 'Partagé avec succès'
                : (isEs ? 'Compartido con éxito' : 'Shared successfully')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFr
                ? 'Erreur de partage'
                : (isEs ? 'Error al compartir' : 'Export failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  String _buildShareText(bool isEs, {bool isFr = false}) {
    if (_results == null) return '';
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

    if (isFr) {
      return '''
HELOC Calculator — Résultats

Valeur de la propriété : ${AmountFormatter.ui(homeValue, 'USD')}
Solde hypothécaire : ${AmountFormatter.ui(mortgage, 'USD')}
Montant prélevé : ${AmountFormatter.ui(draw, 'USD')}
Taux HELOC : ${rate.toStringAsFixed(2)}%
Période : ${drawYears}a retrait / ${repayYears}a remboursement

Paiement intérêts seulement : ${AmountFormatter.ui(interestOnly, 'USD')}/mois
Paiement amorti : ${AmountFormatter.ui(repayment, 'USD')}/mois
Capitaux propres disponibles : ${AmountFormatter.ui(equity, 'USD')}
RFV actuel : ${_fmtPct.format(ltv)}%
Économies fiscales est. : ${AmountFormatter.ui(taxSavings, 'USD')}/an

⚠ Consultez un conseiller fiscal. Les intérêts HELOC peuvent être déductibles si utilisés pour des améliorations domiciliaires.

📄 Exportez le rapport complet en PDF →
''';
    }
    if (isEs) {
      return '''
HELOC Calculator — Resultado

Valor vivienda: ${AmountFormatter.ui(homeValue, 'USD')}
Saldo hipoteca: ${AmountFormatter.ui(mortgage, 'USD')}
Monto dispuesto: ${AmountFormatter.ui(draw, 'USD')}
Tasa HELOC: ${rate.toStringAsFixed(2)}%
Período: ${drawYears}a disposición / ${repayYears}a pago

Pago solo interés: ${AmountFormatter.ui(interestOnly, 'USD')}/mes
Pago amortizado: ${AmountFormatter.ui(repayment, 'USD')}/mes
Capital disponible: ${AmountFormatter.ui(equity, 'USD')}
LTV actual: ${_fmtPct.format(ltv)}%
Ahorro fiscal estimado: ${AmountFormatter.ui(taxSavings, 'USD')}/año

⚠ Consulta a un asesor fiscal. Los intereses del HELOC pueden ser deducibles si se usan para mejoras del hogar.

📄 Exporta el reporte completo en PDF →
''';
    }
    return '''
HELOC Calculator — Results

Home Value: ${AmountFormatter.ui(homeValue, 'USD')}
Mortgage Balance: ${AmountFormatter.ui(mortgage, 'USD')}
Draw Amount: ${AmountFormatter.ui(draw, 'USD')}
HELOC Rate: ${rate.toStringAsFixed(2)}%
Period: ${drawYears}yr draw / ${repayYears}yr repayment

Interest-Only Payment: ${AmountFormatter.ui(interestOnly, 'USD')}/mo
Repayment Payment: ${AmountFormatter.ui(repayment, 'USD')}/mo
Available Equity: ${AmountFormatter.ui(equity, 'USD')}
Current LTV: ${_fmtPct.format(ltv)}%
Est. Tax Savings: ${AmountFormatter.ui(taxSavings, 'USD')}/yr

⚠ Consult a tax advisor. HELOC interest may be deductible if used for home improvements.

📄 Export the full PDF report in the app →
''';
  }

  // ── PDF Export ─────────────────────────────────────────────────────────────

  Future<void> _exportPdf(bool isEs, {bool isFr = false}) async {
    if (_results == null) return;

    if (!freemiumService.hasFullAccess) {
      AnalyticsService.instance.logPaywallHardShown();
      await PaywallHard.show(context);
      return;
    }

    AnalyticsService.instance.logPdfExported();
    try {
      final bytes = await _buildPdf(isEs, isFr: isFr);
      if (!mounted) return;
      await Printing.sharePdf(
        bytes: bytes,
        filename:
            'HELOC_Calculator_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFr
                ? 'PDF exporté avec succès'
                : (isEs ? 'PDF exportado con éxito' : 'PDF exported successfully')),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFr
                ? 'Erreur lors de l\'export PDF'
                : (isEs ? 'Error al exportar PDF' : 'Export failed')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<Uint8List> _buildPdf(bool isEs, {bool isFr = false}) async {
    if (_results == null) return Uint8List(0);
    final r = _results!;
    final params = _CalculatorPdfParams(
      homeValue: (r['homeValue'] as num?)?.toDouble() ?? 0.0,
      mortgage: (r['mortgage'] as num?)?.toDouble() ?? 0.0,
      draw: (r['draw'] as num?)?.toDouble() ?? 0.0,
      rate: (r['rate'] as num?)?.toDouble() ?? 0.0,
      drawYears: (r['drawYears'] as num?)?.toInt() ?? 10,
      repayYears: (r['repayYears'] as num?)?.toInt() ?? 20,
      equity: (r['equity'] as num?)?.toDouble() ?? 0.0,
      ltv: (r['ltv'] as num?)?.toDouble() ?? 0.0,
      interestOnly: (r['interestOnly'] as num?)?.toDouble() ?? 0.0,
      repayment: (r['repayment'] as num?)?.toDouble() ?? 0.0,
      taxSavings: (r['taxSavings'] as num?)?.toDouble() ?? 0.0,
      isEs: isEs,
      isFr: isFr,
      nowMs: DateTime.now().millisecondsSinceEpoch,
    );
    return Isolate.run(() => _buildCalculatorPdf(params));
  }



  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    const isFr = false;

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
                  child: Form(
                    key: _formKey,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // ── A. Result summary (TOP) ───────────────────────────────
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
                                    key: const ValueKey('results_top'),
                                    child: CalcwisePageEntrance(child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Row header: "Results" title
                                        Row(children: [
                                          Expanded(
                                            child: Text(
                                              isEs ? 'Resultados' : 'Results',
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize:
                                                      AppTextSize.bodyLg),
                                            ),
                                          ),
                                        ]),
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
                                          final equity =
                                              _results!['equity'] as double? ??
                                                  0;
                                          final drawYears =
                                              _results!['drawYears'] as int? ??
                                                  10;
                                          return Container(
                                            margin: const EdgeInsets.only(
                                                top: AppSpacing.lg),
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(28),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Theme.of(ctx)
                                                      .colorScheme
                                                      .primary
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: CalcwiseHeroCard(
                                              label: isIO
                                                  ? (isEs
                                                      ? 'Pago Solo Interés'
                                                      : 'Interest-Only Payment')
                                                  : (isEs
                                                      ? 'Pago P&I'
                                                      : 'P&I Payment'),
                                              value: AmountFormatter.ui(
                                                  drawPayment, 'USD'),
                                              rawValue: drawPayment,
                                              valueFormatter: (v) =>
                                                  AmountFormatter.ui(v, 'USD'),
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
                                                  value: AmountFormatter.ui(
                                                      totalInt, 'USD')
                                                ),
                                                (
                                                  label: isEs
                                                      ? 'Capital disponible'
                                                      : 'Available Equity',
                                                  value: AmountFormatter.ui(
                                                      equity, 'USD')
                                                ),
                                              ],
                                              rawStats: [
                                                (
                                                  label: isEs
                                                      ? 'Interés total'
                                                      : 'Total Interest',
                                                  value: totalInt,
                                                  formatter: (v) =>
                                                      AmountFormatter.ui(
                                                          v, 'USD'),
                                                ),
                                                (
                                                  label: isEs
                                                      ? 'Capital disponible'
                                                      : 'Available Equity',
                                                  value: equity,
                                                  formatter: (v) =>
                                                      AmountFormatter.ui(
                                                          v, 'USD'),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        const SizedBox(height: 8),
                                        Card(
                                          elevation: 0,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.xl),
                                            side: BorderSide(
                                                color: Theme.of(context)
                                                    .dividerColor),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.all(
                                                AppSpacing.lg),
                                            child: Column(children: [
                                              MetricRow(
                                                label: isEs
                                                    ? 'Capital disponible (85% LTV)'
                                                    : 'Available Equity (85% LTV)',
                                                value: AmountFormatter.ui(
                                                    (_results!['equity']
                                                            as double?) ??
                                                        0.0,
                                                    'USD'),
                                                valueColor: AppTheme.success,
                                              ),
                                              const Divider(height: 16),
                                              MetricRow(
                                                label: isEs
                                                    ? 'Capacidad máx. préstamo (85%)'
                                                    : 'Max Borrow Capacity (85%)',
                                                value: AmountFormatter.ui(
                                                    (_results!['maxBorrow85']
                                                            as double?) ??
                                                        0.0,
                                                    'USD'),
                                                valueColor: AppTheme.primary,
                                              ),
                                              const Divider(height: 16),
                                              MetricRow(
                                                label: isEs
                                                    ? 'LTV actual'
                                                    : 'Current LTV',
                                                value:
                                                    '${_fmtPct.format(_results!['ltv'])}%',
                                                valueColor:
                                                    (_results!['ltv']
                                                                as double) >
                                                            85
                                                        ? AppTheme.error
                                                        : AppTheme.labelGray,
                                              ),
                                              Builder(builder: (ctx) {
                                                final ltv =
                                                    _results!['ltv'] as double;
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
                                                      decoration: BoxDecoration(
                                                        color: ltvTrafficColor,
                                                        shape: BoxShape.circle,
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
                                                        _PaymentMode.interestOnly
                                                    ? (isEs
                                                        ? 'Interés total estimado'
                                                        : 'Total Interest (Estimated)')
                                                    : (isEs
                                                        ? 'Interés total (P&I completo)'
                                                        : 'Total Interest (Full P&I)'),
                                                value: AmountFormatter.ui(
                                                  (_paymentMode ==
                                                              _PaymentMode
                                                                  .interestOnly
                                                          ? _results![
                                                              'totalInterest']
                                                          : _results![
                                                              'totalInterestFullPI'])
                                                      as double? ??
                                                      0.0,
                                                  'USD',
                                                ),
                                                valueColor: AppTheme.errorDark,
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
                                              color: AppTheme.infoBlue
                                                  .withValues(alpha: 0.08),
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
                                                    Icons.info_outline_rounded,
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
                                                                AppTextSize.sm,
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
                                                              ? 'Ahorro fiscal estimado (${_taxBracket.toStringAsFixed(0)}%): ${AmountFormatter.ui((_results!['taxSavings'] as double?) ?? 0.0, 'USD')}/año'
                                                              : 'Est. tax savings (${_taxBracket.toStringAsFixed(0)}% bracket): ${AmountFormatter.ui((_results!['taxSavings'] as double?) ?? 0.0, 'USD')}/year',
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
                                      ],
                                    )),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('results_top_empty')),
                          ),

                          // ── B. Divider between results summary and form ───────────
                          const Divider(height: 40),

                          // ── C. Form fields ────────────────────────────────────────
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
                            hint: '7.5',
                            validator: (v) => _parseNum(v ?? '') < 0
                                ? (isEs ? 'Tasa inválida' : 'Invalid rate')
                                : null,
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: _taxBracketCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                            ],
                            decoration: InputDecoration(
                              labelText: isEs ? 'Tramo Impositivo (%)' : 'Tax Bracket (%)',
                              hintText: '22',
                              suffixText: '%',
                            ),
                            onChanged: (v) {
                              _taxBracket =
                                  (double.tryParse(v) ?? 22.0).clamp(0.0, 50.0);
                              scheduleCalc(_tryCalculate);
                            },
                            validator: (v) {
                              final val = double.tryParse(v ?? '');
                              if (val == null || val < 0 || val > 50) {
                                return isEs ? 'Valor entre 0 y 50' : 'Enter 0–50';
                              }
                              return null;
                            },
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

                          // ── D. Tools & analysis (below form, only when results available) ──
                          if (_results != null) ...[
                            const SizedBox(height: 24),
                            // Smart Insights
                            InsightCard(
                              insights: InsightEngine.generate(
                                homeValue: (_results!['homeValue']
                                        as double? ??
                                    0),
                                mortgageBalance:
                                    (_results!['mortgage'] as double? ?? 0),
                                helocLimit:
                                    (_results!['draw'] as double? ?? 0),
                                annualRatePct:
                                    (_results!['rate'] as double? ?? 0),
                                drawPayment: (_results!['interestOnly']
                                        as double? ??
                                    0),
                                repaymentPayment:
                                    (_results!['repayment'] as double? ?? 0),
                                totalInterest: (_results!['totalInterest']
                                        as double? ??
                                    0),
                                isEs: isEs,
                              ),
                              isSpanish: isEs,
                            ),
                            const SizedBox(height: 24),
                            _buildRateScenarios(isEs),
                            const SizedBox(height: 24),
                            // HELOC vs Home Equity Loan comparison
                            _buildHelVsHeloc(isEs),
                            const SizedBox(height: 24),
                            // Feature 3 — Interest-Only vs Fully Amortizing
                            _IoVsFullyAmortizingCard(
                              draw: (_results!['draw'] as double?) ?? 0,
                              rate: (_results!['rate'] as double?) ?? 0,
                              drawYears:
                                  (_results!['drawYears'] as int?) ?? 10,
                              repayYears:
                                  (_results!['repayYears'] as int?) ?? 20,
                              isEs: isEs,
                            ),
                            const SizedBox(height: 24),
                            // Feature 1 — Rate Sensitivity sliders
                            ValueListenableBuilder<bool>(
                              valueListenable:
                                  freemiumService.hasFullAccessNotifier,
                              builder: (_, isPremium, __) {
                                if (!isPremium) {
                                  return CalcwisePremiumGate(
                                    title: isEs
                                        ? 'Sensibilidad de Tasa'
                                        : 'Rate Sensitivity',
                                    description: isEs
                                        ? 'Simula el impacto de cambios de tasa en tu pago mensual e interés total.'
                                        : 'Simulate how rate changes impact your monthly payment and total interest.',
                                    onUnlock: () {
                                      AnalyticsService.instance.logPaywallHardShown();
                                      PaywallHard.show(context);
                                    },
                                    price:
                                        IAPService.instance.localizedPrice,
                                  );
                                }
                                return _RateSensitivityWidget(
                                  draw: (_results!['draw'] as double?) ?? 0,
                                  baseRate:
                                      (_results!['rate'] as double?) ?? 0,
                                  drawYears:
                                      (_results!['drawYears'] as int?) ?? 10,
                                  repayYears:
                                      (_results!['repayYears'] as int?) ?? 20,
                                  isEs: isEs,
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            SaveScenarioButton(onSave: _saveScenario),
                            const SizedBox(height: 8),
                            // ── Grouped action bar: Share + Export ──────────────
                            Row(children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _share(isEs, isFr: isFr),
                                  icon: const Icon(Icons.share_rounded,
                                      size: 18),
                                  label: Text(isEs ? 'Compartir' : 'Share'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 44),
                                    foregroundColor: AppTheme.primary,
                                    side: const BorderSide(
                                        color: AppTheme.primary),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(
                                            AppRadius.xl)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: ValueListenableBuilder<bool>(
                                  valueListenable:
                                      freemiumService.hasFullAccessNotifier,
                                  builder: (_, isPremium, __) =>
                                      OutlinedButton.icon(
                                    onPressed: () =>
                                        _exportPdf(isEs, isFr: isFr),
                                    icon: Icon(
                                      Icons.picture_as_pdf_rounded,
                                      size: 18,
                                      color: isPremium
                                          ? AppTheme.primary
                                          : AppTheme.labelGray,
                                    ),
                                    label: Text(isEs
                                        ? AppStringsES.exportPdf
                                        : AppStringsEN.exportPdf),
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 44),
                                      foregroundColor: isPremium
                                          ? AppTheme.primary
                                          : AppTheme.labelGray,
                                      side: BorderSide(
                                          color: isPremium
                                              ? AppTheme.primary
                                              : AppTheme.labelGray),
                                      shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              AppRadius.xl)),
                                    ),
                                  ),
                                ),
                              ),
                            ]),
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
                                side:
                                    const BorderSide(color: AppTheme.primary),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(AppRadius.xl)),
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ],
                    ),
                  ),
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

    // Color per offset: -1=green, 0=primary, +1=amber, +2=red
    Color cardColorForOffset(int offset) {
      if (offset < 0) return AppTheme.successDark;
      if (offset == 0) return AppTheme.primary;
      if (offset == 1) return _chartAmberColor;
      return AppTheme.errorDark;
    }

    String labelForOffset(int offset, bool es) {
      if (offset < 0)
        return es ? 'Bajan ${-offset}%' : 'Rates drop ${-offset}%';
      if (offset == 0) return es ? 'Tasa actual' : 'Current rate';
      return es ? 'Suben $offset%' : 'Rates rise $offset%';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Icon(Icons.show_chart_rounded,
              size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: AppTextSize.bodyMd, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          height: 192,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _cachedScenarios!.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (ctx, i) {
              final scenario = _cachedScenarios![i];
              final offset = scenario['offset'] as int;
              final scenarioRate = scenario['scenarioRate'] as double;
              final drawPmt = scenario['drawPmt'] as double;
              final repayPmt = scenario['repayPmt'] as double;
              final isCurrent = offset == 0;
              final cardColor = cardColorForOffset(offset);

              return Container(
                width: 148,
                padding: const EdgeInsets.all(AppSpacing.mdPlus),
                decoration: BoxDecoration(
                  color:
                      isCurrent ? cardColor : cardColor.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  border: Border.all(
                      color: cardColor.withValues(alpha: isCurrent ? 0 : 0.4),
                      width: 1.5),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      labelForOffset(offset, isEs),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        fontWeight: FontWeight.w600,
                        color: isCurrent
                            ? Colors.white.withValues(alpha: 0.85)
                            : cardColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${scenarioRate.toStringAsFixed(1)}%',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSize.subtitle,
                        fontWeight: FontWeight.w900,
                        color: isCurrent ? Colors.white : cardColor,
                      ),
                    ),
                    const Spacer(),
                    // Draw payment
                    Text(
                      isEs ? 'Interés' : 'Draw pmt',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: isCurrent
                            ? Colors.white70
                            : CalcwiseTheme.of(ctx).textSecondary,
                      ),
                    ),
                    Text(
                      '${AmountFormatter.ui(drawPmt, 'USD')}/mo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? Colors.white : cardColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // Repayment
                    Text(
                      isEs ? 'Amortizado' : 'Repay pmt',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color: isCurrent
                            ? Colors.white70
                            : CalcwiseTheme.of(ctx).textSecondary,
                      ),
                    ),
                    Text(
                      '${AmountFormatter.ui(repayPmt, 'USD')}/mo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppTextSize.sm,
                        fontWeight: FontWeight.w700,
                        color: isCurrent ? Colors.white : cardColor,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// HELOC vs Home Equity Loan comparison section.
  Widget _buildHelVsHeloc(bool isEs) {
    if (_results == null) return const SizedBox.shrink();
    final draw = (_results!['draw'] as double?) ?? 0;
    final helocRate = (_results!['rate'] as double?) ?? 0;
    final drawYears = (_results!['drawYears'] as int?) ?? 10;
    final repayYears = (_results!['repayYears'] as int?) ?? 20;
    if (draw <= 0 || helocRate <= 0) return const SizedBox.shrink();

    // HEL: fixed rate — assume same principal, rate +0.5% (typical HEL spread)
    final helRate = helocRate + 0.5;
    final helTermYears = repayYears; // same repayment horizon
    final helMonthly =
        HelocEngine.amortizedPayment(draw, helRate, helTermYears);
    final helTotalInterest = helMonthly * helTermYears * 12 - draw;

    // HELOC: total interest across both phases
    final helocTotalInterest =
        HelocEngine.totalInterestPaid(draw, helocRate, drawYears, repayYears);
    final helocDrawPmt = HelocEngine.interestOnlyPayment(draw, helocRate);
    final helocRepayPmt =
        HelocEngine.amortizedPayment(draw, helocRate, repayYears);

    final helocCheaper = helocTotalInterest < helTotalInterest;
    final verdictColor =
        helocCheaper ? AppTheme.successDark : AppTheme.errorDark;

    Widget _row(String left, String center, String right,
        {bool header = false}) {
      final style = TextStyle(
        fontSize: header ? AppTextSize.xs : AppTextSize.sm,
        fontWeight: header ? FontWeight.w700 : FontWeight.w500,
        color: header ? AppTheme.primary : null,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(flex: 3, child: Text(left, style: style)),
          Expanded(
              flex: 2,
              child: Text(center, textAlign: TextAlign.center, style: style)),
          Expanded(
              flex: 2,
              child: Text(right, textAlign: TextAlign.right, style: style)),
        ]),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Row(children: [
              const Icon(Icons.balance_rounded,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEs
                      ? 'HELOC vs Préstamo Sobre Valor'
                      : 'HELOC vs Home Equity Loan',
                  style: const TextStyle(
                      fontSize: AppTextSize.bodyMd,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              isEs
                  ? 'HELOC: línea revolvente tasa variable. HEL: monto fijo, tasa fija.'
                  : 'HELOC: revolving variable-rate line. HEL: lump-sum fixed-rate loan.',
              style: const TextStyle(
                  fontSize: AppTextSize.xs,
                  color: AppTheme.labelGray,
                  height: 1.4),
            ),
            const SizedBox(height: 14),

            // Comparison table
            _row(
              '',
              'HELOC',
              isEs ? 'HEL (fijo)' : 'HEL (fixed)',
              header: true,
            ),
            const Divider(height: 10),
            _row(
              isEs ? 'Tasa' : 'Rate',
              '${helocRate.toStringAsFixed(2)}% (var)',
              '${helRate.toStringAsFixed(2)}% (fixed)',
            ),
            _row(
              isEs ? 'Pago fase disponer' : 'Draw phase pmt',
              '${AmountFormatter.ui(helocDrawPmt, 'USD')}/mo',
              '${AmountFormatter.ui(helMonthly, 'USD')}/mo',
            ),
            _row(
              isEs ? 'Pago amortización' : 'Repay phase pmt',
              '${AmountFormatter.ui(helocRepayPmt, 'USD')}/mo',
              '${AmountFormatter.ui(helMonthly, 'USD')}/mo',
            ),
            _row(
              isEs ? 'Interés total est.' : 'Total interest est.',
              AmountFormatter.ui(helocTotalInterest, 'USD'),
              AmountFormatter.ui(helTotalInterest, 'USD'),
            ),
            _row(
              isEs ? 'Flexibilidad' : 'Flexibility',
              isEs ? 'Alta' : 'High',
              isEs ? 'Baja' : 'Low',
            ),
            const SizedBox(height: 12),

            // Verdict banner
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: verdictColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(color: verdictColor.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    helocCheaper
                        ? (isEs
                            ? '✅ Para tu escenario, el HELOC tiene menor interés total'
                            : '✅ For your scenario, HELOC costs less total interest')
                        : (isEs
                            ? '💡 Para tu escenario, el HEL tiene menor interés total'
                            : '💡 For your scenario, the HEL costs less total interest'),
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTextSize.sm,
                      color: verdictColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isEs
                        ? 'Elige HELOC si necesitas acceso flexible a fondos. Elige HEL para pagos fijos y predecibles.'
                        : 'Choose HELOC if you need flexible access to funds. Choose HEL for predictable fixed payments.',
                    style: TextStyle(
                      fontSize: AppTextSize.xs,
                      color: verdictColor.withValues(alpha: 0.8),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
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
                  color: CalcwiseSemanticColors.warnBg,
                  borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                  border: Border.all(color: CalcwiseSemanticColors.warnBorder),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.star_rounded,
                      color: CalcwiseSemanticColors.warnIcon, size: 12),
                  const SizedBox(width: 3),
                  Text('Premium',
                      style: const TextStyle(
                          fontSize: AppTextSize.xs,
                          color: CalcwiseSemanticColors.warnIcon,
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
                    value: AmountFormatter.ui(_newMonthly, 'USD'),
                    delta: paymentDelta,
                    color: arrowColor,
                    isEs: isEs,
                  ),
                  const Divider(height: 16),
                  _SensRow(
                    label:
                        isEs ? 'Delta interés total' : 'Total interest delta',
                    value: AmountFormatter.ui(_newTotal, 'USD'),
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
    final radius = BorderRadius.circular(AppRadius.xxl);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color:
                isSelected ? color.withValues(alpha: 0.12) : Colors.transparent,
            borderRadius: radius,
            border: Border.all(
              color: isSelected ? color : CalcwiseTheme.of(context).cardBorder,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTextSize.sm,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? color : AppTheme.labelGray,
              ),
            ),
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
          style: const TextStyle(fontSize: AppTextSize.xs, color: AppTheme.labelGray),
        ),
        Text(
          '$sign${AmountFormatter.ui(delta, 'USD')}',
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
        ioTotalInterest; // totalDiff > 0 means FA costs more; totalDiff < 0 means IO costs more (typical: IO defers principal so accumulates more interest)

    // IO: lower monthly during draw but higher total; FA: higher monthly but lower total

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
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
                    color: _helocScenarioColor.withValues(alpha: 0.09),
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
                          color: _helocScenarioColor,
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
              val1: AmountFormatter.ui(ioDrawPayment, 'USD'),
              val2: AmountFormatter.ui(faMonthly, 'USD'),
              winner: ioDrawPayment < faMonthly ? 0 : 1,
            ),
            _CompRow(
              label: isEs
                  ? 'Pago mensual\n(fase de pago)'
                  : 'Monthly payment\n(repay phase)',
              val1: AmountFormatter.ui(ioRepayPayment, 'USD'),
              val2: AmountFormatter.ui(faMonthly, 'USD'),
              winner: ioRepayPayment < faMonthly ? 0 : 1,
            ),
            _CompRow(
              label: isEs ? 'Interés total' : 'Total interest',
              val1: AmountFormatter.ui(ioTotalInterest, 'USD'),
              val2: AmountFormatter.ui(faTotalInterest, 'USD'),
              highlight: true,
              winner: ioTotalInterest < faTotalInterest ? 0 : 1,
            ),
            _CompRow(
              label: isEs ? 'Total pagado' : 'Total paid',
              val1: AmountFormatter.ui(ioTotalPaid, 'USD'),
              val2: AmountFormatter.ui(faTotalPaid, 'USD'),
              winner: ioTotalPaid < faTotalPaid ? 0 : 1,
            ),

            const SizedBox(height: 16),

            // Verdict badge
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: CalcwiseSemanticColors.warnBg,
                borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                border: Border.all(color: CalcwiseSemanticColors.warnBorder),
              ),
              child: Row(children: [
                const Icon(Icons.lightbulb_outline,
                    color: CalcwiseSemanticColors.warnIcon, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isEs
                        ? 'Solo interés ahorra ${AmountFormatter.ui(monthlyDraw.abs(), 'USD')}/mes ahora, '
                            'pero cuesta ${AmountFormatter.ui(totalDiff.abs(), 'USD')} ${totalDiff < 0 ? "más" : "menos"} en total.'
                        : 'Interest-only saves ${AmountFormatter.ui(monthlyDraw.abs(), 'USD')}/mo now, '
                            'costs ${AmountFormatter.ui(totalDiff.abs(), 'USD')} ${totalDiff < 0 ? "more" : "less"} total.',
                    style: const TextStyle(
                        fontSize: AppTextSize.sm,
                        color: CalcwiseSemanticColors.alertText,
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
                _Cell(val2, winner == 1, highlight, _helocScenarioColor)),
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
