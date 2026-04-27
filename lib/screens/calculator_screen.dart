import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../core/ads/ad_service.dart';
import '../core/db/database_service.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/paywall_service.dart';
import '../core/heloc_engine.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../widgets/result_card.dart';

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

class _CalculatorScreenState extends State<CalculatorScreen> {
  final _formKey = GlobalKey<FormState>();

  final _homeValueCtrl = TextEditingController(text: '500000');
  final _mortgageCtrl = TextEditingController(text: '200000');
  final _drawCtrl = TextEditingController(text: '100000');
  final _rateCtrl = TextEditingController(text: '8.5');
  final _drawYearsCtrl = TextEditingController(text: '10');
  final _repayYearsCtrl = TextEditingController(text: '20');

  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _fmtDec = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtPct = NumberFormat('##0.0#');

  // Live computed equity
  double _availableEquity = 200000;
  double _ltvPct = 40;

  Map<String, dynamic>? _results;

  @override
  void initState() {
    super.initState();
    _homeValueCtrl.addListener(_updateEquity);
    _mortgageCtrl.addListener(_updateEquity);
    for (final c in [_homeValueCtrl, _mortgageCtrl, _drawCtrl, _rateCtrl,
                     _drawYearsCtrl, _repayYearsCtrl]) {
      c.addListener(_tryCalculate);
    }
    _updateEquity();
  }

  void _updateEquity() {
    final homeValue = _parseNum(_homeValueCtrl.text);
    final mortgage = _parseNum(_mortgageCtrl.text);
    final equity = HelocEngine.availableEquity(homeValue, mortgage);
    final ltv = HelocEngine.ltv(mortgage, homeValue);
    if (mounted) setState(() { _availableEquity = equity; _ltvPct = ltv; });
  }

  void _tryCalculate() {
    final homeValue = _parseNum(_homeValueCtrl.text);
    final mortgage = _parseNum(_mortgageCtrl.text);
    final draw = _parseNum(_drawCtrl.text);
    final rate = _parseNum(_rateCtrl.text);
    final drawYears = int.tryParse(_drawYearsCtrl.text) ?? 0;
    final repayYears = int.tryParse(_repayYearsCtrl.text) ?? 0;
    if (homeValue <= 0 || draw <= 0 || rate <= 0 || drawYears <= 0 || repayYears <= 0) return;
    final equity = HelocEngine.availableEquity(homeValue, mortgage);
    final ltv = HelocEngine.ltv(mortgage, homeValue);
    final interestOnly = HelocEngine.interestOnlyPayment(draw, rate);
    final repayment = HelocEngine.amortizedPayment(draw, rate, repayYears);
    final totalInterest = HelocEngine.totalInterestPaid(draw, rate, drawYears, repayYears);
    final maxBorrow85 = HelocEngine.maxBorrowCapacity(homeValue, mortgage, ltvLimit: 0.85);
    final taxSavings = HelocEngine.estimatedAnnualTaxSavings(draw, rate, 22.0);
    if (!mounted) return;
    setState(() {
      _results = {
        'homeValue': homeValue, 'mortgage': mortgage, 'draw': draw, 'rate': rate,
        'drawYears': drawYears, 'repayYears': repayYears,
        'equity': equity, 'ltv': ltv, 'interestOnly': interestOnly,
        'repayment': repayment, 'totalInterest': totalInterest,
        'maxBorrow85': maxBorrow85, 'taxSavings': taxSavings,
      };
    });
  }

  @override
  void dispose() {
    _homeValueCtrl.removeListener(_updateEquity);
    _mortgageCtrl.removeListener(_updateEquity);
    for (final c in [_homeValueCtrl, _mortgageCtrl, _drawCtrl, _rateCtrl,
                     _drawYearsCtrl, _repayYearsCtrl]) {
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

  void _calculate() {
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
    final totalInterest = HelocEngine.totalInterestPaid(draw, rate, drawYears, repayYears);
    final maxBorrow85 = HelocEngine.maxBorrowCapacity(homeValue, mortgage, ltvLimit: 0.85);
    final taxSavings = HelocEngine.estimatedAnnualTaxSavings(draw, rate, 22.0);

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
      };
    });

    AdService.instance.onCalculation();
    AnalyticsService.instance.logCalculation(
      homeValue: homeValue,
      ratePct: rate,
    );
    final trigger = paywallService.recordAction();
    if (trigger != PaywallTrigger.none && mounted && !freemiumService.isPremium) {
      if (trigger == PaywallTrigger.soft) {
        PaywallSoft.show(context);
      } else {
        PaywallHard.show(context);
      }
    }

    DatabaseService.instance.insertHistory(
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
  }

  void _reset() {
    _homeValueCtrl.text = '500000';
    _mortgageCtrl.text = '200000';
    _drawCtrl.text = '100000';
    _rateCtrl.text = '8.5';
    _drawYearsCtrl.text = '10';
    _repayYearsCtrl.text = '20';
    setState(() => _results = null);
  }

  // ── Share ──────────────────────────────────────────────────────────────────

  void _share(bool isEs) {
    if (_results == null) return;

    if (!freemiumService.isPremium) {
      final trigger = paywallService.recordAction();
      if (trigger == PaywallTrigger.hard) {
        PaywallHard.show(context);
        return;
      } else if (trigger == PaywallTrigger.soft) {
        PaywallSoft.show(context);
        // share anyway (soft paywall)
      }
    }

    final text = _buildShareText(isEs);
    Share.share(text);
  }

  String _buildShareText(bool isEs) {
    final r = _results!;
    final homeValue = r['homeValue'] as double;
    final mortgage = r['mortgage'] as double;
    final draw = r['draw'] as double;
    final rate = r['rate'] as double;
    final drawYears = r['drawYears'] as int;
    final repayYears = r['repayYears'] as int;
    final equity = r['equity'] as double;
    final ltv = r['ltv'] as double;
    final interestOnly = r['interestOnly'] as double;
    final repayment = r['repayment'] as double;
    final taxSavings = r['taxSavings'] as double;

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

    if (!freemiumService.isPremium) {
      await PaywallHard.show(context);
      return;
    }

    AnalyticsService.instance.logPdfExported();
    final bytes = await _buildPdf(isEs);
    if (!mounted) return;
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'HELOC_Calculator_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
    );
  }

  Future<Uint8List> _buildPdf(bool isEs) async {
    final r = _results!;
    final homeValue = r['homeValue'] as double;
    final mortgage = r['mortgage'] as double;
    final draw = r['draw'] as double;
    final rate = r['rate'] as double;
    final drawYears = r['drawYears'] as int;
    final repayYears = r['repayYears'] as int;
    final equity = r['equity'] as double;
    final ltv = r['ltv'] as double;
    final interestOnly = r['interestOnly'] as double;
    final repayment = r['repayment'] as double;
    final taxSavings = r['taxSavings'] as double;
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
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFF00695C),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'HELOC Calculator',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                    pw.Text(
                      dateFmt.format(now),
                      style: const pw.TextStyle(
                          fontSize: 12, color: PdfColors.white),
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
                        ['Pago solo interés (período disposición)', _fmtDec.format(interestOnly)],
                        ['Pago amortizado (período de pago)', _fmtDec.format(repayment)],
                        ['Capital disponible (85% LTV)', _fmt.format(equity)],
                        ['LTV actual', '${_fmtPct.format(ltv)}%'],
                        ['Ahorro fiscal estimado (22%)', '${_fmtDec.format(taxSavings)}/año'],
                      ]
                    : [
                        ['Interest-Only Payment (Draw Period)', _fmtDec.format(interestOnly)],
                        ['Repayment Payment (After Draw)', _fmtDec.format(repayment)],
                        ['Available Equity (85% LTV)', _fmt.format(equity)],
                        ['Current LTV', '${_fmtPct.format(ltv)}%'],
                        ['Est. Tax Savings (22% bracket)', '${_fmtDec.format(taxSavings)}/year'],
                      ],
                highlightFirst: true,
              ),
              pw.SizedBox(height: 20),

              // Tax deductibility note
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: const PdfColor.fromInt(0xFFE3F2FD),
                  borderRadius: pw.BorderRadius.circular(6),
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
                        fontSize: 11,
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
                          fontSize: 10,
                          color: PdfColor.fromInt(0xFF1565C0)),
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
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 13,
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
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
              child: pw.Text(e.value[0],
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8, vertical: 6),
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

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEs ? 'Información de la Vivienda' : 'Home Information',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 14),

                  _buildField(
                    controller: _homeValueCtrl,
                    label: isEs ? 'Valor de la vivienda (\$)' : 'Home Value (\$)',
                    hint: '500000',
                    validator: (v) => _parseNum(v ?? '') <= 0
                        ? (isEs ? 'Ingresa un valor' : 'Enter a value')
                        : null,
                  ),
                  const SizedBox(height: 14),

                  _buildField(
                    controller: _mortgageCtrl,
                    label: isEs ? 'Saldo hipotecario actual (\$)' : 'Current Mortgage Balance (\$)',
                    hint: '200000',
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 14),

                  _buildField(
                    controller: _drawCtrl,
                    label: isEs ? 'Monto a disponer (\$)' : 'Draw Amount (\$)',
                    hint: '100000',
                    validator: (v) {
                      final val = _parseNum(v ?? '');
                      if (val <= 0) {
                        return isEs ? 'Ingresa un monto' : 'Enter amount';
                      }
                      if (val > _availableEquity) {
                        return isEs
                            ? 'Excede el capital disponible'
                            : 'Exceeds available equity';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),

                  _buildField(
                    controller: _rateCtrl,
                    label: isEs ? 'Tasa HELOC (%)' : 'HELOC Rate (%)',
                    hint: '8.5',
                    validator: (v) => _parseNum(v ?? '') < 0
                        ? (isEs ? 'Tasa inválida' : 'Invalid rate')
                        : null,
                  ),
                  const SizedBox(height: 14),

                  Row(children: [
                    Expanded(
                      child: _buildField(
                        controller: _drawYearsCtrl,
                        label: isEs ? 'Período de disposición (años)' : 'Draw Period (years)',
                        hint: '10',
                        intOnly: true,
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                            ? (isEs ? 'Inválido' : 'Invalid')
                            : null,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: _buildField(
                        controller: _repayYearsCtrl,
                        label: isEs ? 'Período de pago (años)' : 'Repayment Period (years)',
                        hint: '20',
                        intOnly: true,
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0
                            ? (isEs ? 'Inválido' : 'Invalid')
                            : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: _calculate,
                    icon: const Icon(Icons.calculate),
                    label: Text(isEs ? AppStringsES.calculate : AppStringsEN.calculate),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(isEs ? AppStringsES.reset : AppStringsEN.reset),
                  ),

                  // Results
                  if (_results != null) ...[
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEs ? AppStringsES.results : AppStringsEN.results,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 18),
                          ),
                        ),
                        // Share button
                        IconButton(
                          icon: const Icon(Icons.share_outlined,
                              color: AppTheme.primary),
                          tooltip: isEs ? 'Compartir' : 'Share',
                          onPressed: () => _share(isEs),
                        ),
                        // PDF export button
                        ValueListenableBuilder<bool>(
                          valueListenable: freemiumService.isPremiumNotifier,
                          builder: (_, isPremium, __) => IconButton(
                            icon: Icon(
                              Icons.picture_as_pdf_outlined,
                              color: isPremium
                                  ? AppTheme.primary
                                  : AppTheme.labelGray,
                            ),
                            tooltip: isPremium
                                ? (isEs
                                    ? AppStringsES.exportPdf
                                    : AppStringsEN.exportPdf)
                                : (isEs
                                    ? AppStringsES.exportLocked
                                    : AppStringsEN.exportLocked),
                            onPressed: () => _exportPdf(isEs),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    ResultCard(
                      highlight: true,
                      label: isEs
                          ? 'Pago Solo Interés (período disposición)'
                          : 'Interest-Only Payment (Draw Period)',
                      value: _fmtDec.format(_results!['interestOnly']),
                      icon: Icons.payments_outlined,
                    ),
                    const SizedBox(height: 10),
                    ResultCard(
                      label: isEs
                          ? 'Pago Amortizado (período de pago)'
                          : 'Repayment Payment (After Draw)',
                      value: _fmtDec.format(_results!['repayment']),
                      icon: Icons.account_balance,
                    ),
                    const SizedBox(height: 10),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          MetricRow(
                            label: isEs ? 'Capital disponible (85% LTV)' : 'Available Equity (85% LTV)',
                            value: _fmt.format(_results!['equity']),
                            valueColor: AppTheme.success,
                          ),
                          const Divider(height: 16),
                          MetricRow(
                            label: isEs ? 'Capacidad máx. préstamo (85%)' : 'Max Borrow Capacity (85%)',
                            value: _fmt.format(_results!['maxBorrow85']),
                            valueColor: AppTheme.primary,
                          ),
                          const Divider(height: 16),
                          MetricRow(
                            label: isEs ? 'LTV actual' : 'Current LTV',
                            value: '${_fmtPct.format(_results!['ltv'])}%',
                            valueColor: (_results!['ltv'] as double) > 85
                                ? Colors.red
                                : AppTheme.labelGray,
                          ),
                          const Divider(height: 16),
                          MetricRow(
                            label: isEs ? 'Interés total estimado' : 'Total Interest (Estimated)',
                            value: _fmt.format(_results!['totalInterest']),
                            valueColor: Colors.red.shade700,
                          ),
                        ]),
                      ),
                    ),
                    // Tax savings + info banner
                    ValueListenableBuilder<bool>(
                      valueListenable: isSpanishNotifier,
                      builder: (_, isSpanish, __) => Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline_rounded, color: Colors.blue.shade700, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    isSpanish
                                        ? 'Los intereses del HELOC pueden ser deducibles de impuestos si se usan para mejoras del hogar. Consulta a un asesor fiscal.'
                                        : 'HELOC interest may be tax-deductible if used for home improvements. Consult a tax advisor.',
                                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800, height: 1.4),
                                  ),
                                  if ((_results?['taxSavings'] as double? ?? 0) > 0) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      isSpanish
                                          ? 'Ahorro fiscal estimado (22%): ${_fmtDec.format(_results!['taxSavings'])}/año'
                                          : 'Est. tax savings (22% bracket): ${_fmtDec.format(_results!['taxSavings'])}/year',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue.shade800,
                                          fontWeight: FontWeight.w600,
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
                    const SizedBox(height: 20),
                    _buildRateScenarios(isEs),
                  ],

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ),
        const BannerAdWidget(),
      ],
    );
  }

  Widget _buildRateScenarios(bool isEs) {
    if (_results == null) return const SizedBox.shrink();
    final draw = (_results!['draw'] as double?) ?? 0;
    final baseRate = (_results!['rate'] as double?) ?? 0;
    final drawYears = (_results!['drawYears'] as int?) ?? 10;
    final repayYears = (_results!['repayYears'] as int?) ?? 20;
    if (baseRate <= 0) return const SizedBox.shrink();

    final offsets = [-3, -2, -1, 0, 1, 2, 3];
    final title = isEs ? 'Escenarios de Tasa' : 'Rate Scenarios';
    final fmtShort = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.compare_arrows, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            // Header row
            Row(children: [
              Expanded(
                flex: 2,
                child: Text(isEs ? 'Tasa' : 'Rate',
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
              Expanded(
                flex: 3,
                child: Text(isEs ? 'Interés' : 'Draw Pmt',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
              Expanded(
                flex: 3,
                child: Text(isEs ? 'Amortizado' : 'Repay Pmt',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
              Expanded(
                flex: 3,
                child: Text(isEs ? 'Int. Total' : 'Total Int.',
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.labelGray)),
              ),
            ]),
            const SizedBox(height: 6),
            ...offsets.map((offset) {
              final scenarioRate = (baseRate + offset).clamp(0.01, 100.0);
              final isCurrent = offset == 0;
              final isBelow = offset < 0;
              final drawPmt = HelocEngine.interestOnlyPayment(draw, scenarioRate);
              final repayPmt = HelocEngine.amortizedPayment(draw, scenarioRate, repayYears);
              final totalInt = HelocEngine.totalInterestPaid(draw, scenarioRate, drawYears, repayYears);
              final textColor = isCurrent
                  ? AppTheme.primary
                  : isBelow
                      ? Colors.green.shade700
                      : Colors.red.shade700;
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 8),
                decoration: isCurrent
                    ? BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(8),
                      )
                    : null,
                child: Row(children: [
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${scenarioRate.toStringAsFixed(1)}%${isCurrent ? (isEs ? " ✦" : " ✦") : ""}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                          color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtShort.format(drawPmt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                          color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtShort.format(repayPmt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
                          color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtShort.format(totalInt),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent ? FontWeight.w700 : FontWeight.normal,
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: intOnly
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
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
    final equityColor = availableEquity > 0 ? AppTheme.success : Colors.orange;
    final ltvColor = isOverLtv ? Colors.red : AppTheme.success;
    final ltvFraction = (ltvPct / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primary.withValues(alpha: 0.08),
            AppTheme.primary.withValues(alpha: 0.03),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.account_balance_wallet_outlined,
                color: AppTheme.primary, size: 18),
            const SizedBox(width: 8),
            Text(
              isEs ? 'Tu capital disponible (85% LTV)' : 'Your available equity (85% LTV)',
              style: TextStyle(
                  fontSize: 12,
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
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: equityColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: ClipRoundedRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: ltvFraction,
                  minHeight: 7,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(ltvColor),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'LTV ${fmtPct.format(ltvPct)}%',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ltvColor,
              ),
            ),
          ]),
          if (isOverLtv) ...[
            const SizedBox(height: 6),
            Text(
              isEs
                  ? '⚠ LTV superior al 85% — sin capital HELOC disponible'
                  : '⚠ LTV above 85% — no HELOC equity available',
              style: const TextStyle(fontSize: 11, color: Colors.red),
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
