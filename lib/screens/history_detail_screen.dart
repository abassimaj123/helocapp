import 'dart:isolate';
import 'dart:math' show pow;
import 'dart:typed_data';

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart' show Share;

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';

// -- PDF params (only sendable primitives) ------------------------------------

class _HistoryDetailPdfParams {
  final double homeValue;
  final double balance;
  final double draw;
  final double rate;
  final int drawYears;
  final int repayYears;
  final double equity;
  final double ltv;
  final double interestOnly;
  final double repayment;
  final double totalInterest;
  final double taxSavings;
  final bool isEs;
  final int createdAtMs;
  const _HistoryDetailPdfParams({
    required this.homeValue,
    required this.balance,
    required this.draw,
    required this.rate,
    required this.drawYears,
    required this.repayYears,
    required this.equity,
    required this.ltv,
    required this.interestOnly,
    required this.repayment,
    required this.totalInterest,
    required this.taxSavings,
    required this.isEs,
    required this.createdAtMs,
  });
}

// -- Top-level PDF builder (runs in Isolate) ----------------------------------

pw.Widget _histPdfSectionTitle(String title) {
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

pw.Widget _histPdfTable(List<List<String>> rows, {bool highlightFirst = false}) {
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
            child: pw.Text(
              e.value[0],
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
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

Future<Uint8List> _buildHistoryDetailPdf(_HistoryDetailPdfParams p) async {
  final fmtPct = NumberFormat('##0.0#');
  final dateFmt = DateFormat('MMM d, yyyy');
  final createdAt = DateTime.fromMillisecondsSinceEpoch(p.createdAtMs);

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
                    p.isEs ? 'HELOC Calculator' : 'HELOC Calculator',
                    style: pw.TextStyle(
                      fontSize: AppTextSize.title,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.Text(
                    dateFmt.format(createdAt.toLocal()),
                    style: const pw.TextStyle(
                      fontSize: AppTextSize.sm,
                      color: PdfColors.white,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),

            // Inputs section
            _histPdfSectionTitle(p.isEs ? 'Datos de Entrada' : 'Input Parameters'),
            pw.SizedBox(height: 8),
            _histPdfTable(
              p.isEs
                  ? [
                      ['Valor de la vivienda', AmountFormatter.ui(p.homeValue, 'USD')],
                      ['Saldo hipotecario', AmountFormatter.ui(p.balance, 'USD')],
                      ['Monto a disponer', AmountFormatter.ui(p.draw, 'USD')],
                      ['Tasa HELOC', '${p.rate.toStringAsFixed(2)}%'],
                      ['Periodo de disposicion', '${p.drawYears} años'],
                      ['Periodo de pago', '${p.repayYears} años'],
                    ]
                  : [
                      ['Home Value', AmountFormatter.ui(p.homeValue, 'USD')],
                      ['Mortgage Balance', AmountFormatter.ui(p.balance, 'USD')],
                      ['Draw Amount', AmountFormatter.ui(p.draw, 'USD')],
                      ['HELOC Rate', '${p.rate.toStringAsFixed(2)}%'],
                      ['Draw Period', '${p.drawYears} years'],
                      ['Repayment Period', '${p.repayYears} years'],
                    ],
            ),
            pw.SizedBox(height: 20),

            // Results section
            _histPdfSectionTitle(p.isEs ? 'Resultados' : 'Results'),
            pw.SizedBox(height: 8),
            _histPdfTable(
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
                      [
                        'Capital disponible (85% LTV)',
                        AmountFormatter.ui(p.equity, 'USD')
                      ],
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
                  color: const PdfColor.fromInt(0xFF1565C0),
                  width: 0.5,
                ),
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
                        ? 'Los intereses del HELOC pueden ser deducibles de impuestos si los fondos se utilizan para mejoras sustanciales del hogar. El ahorro fiscal estimado se basa en un tramo impositivo del 22%. Consulte a un asesor fiscal calificado para obtener asesoramiento personalizado.'
                        : 'HELOC interest may be tax-deductible when funds are used for substantial home improvements. Estimated tax savings are based on the 22% tax bracket. Consult a qualified tax advisor for personalized guidance.',
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColor.fromInt(0xFF1565C0),
                    ),
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
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

class HistoryDetailScreen extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onDelete;

  const HistoryDetailScreen({
    super.key,
    required this.entry,
    required this.onDelete,
  });

  static Future<void> push(
    BuildContext context, {
    required Map<String, dynamic> entry,
    required VoidCallback onDelete,
  }) {
    return Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            HistoryDetailScreen(entry: entry, onDelete: onDelete),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: AppDuration.base,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _HistoryDetailBody(entry: entry, onDelete: onDelete);
  }
}

class _HistoryDetailBody extends StatefulWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onDelete;

  const _HistoryDetailBody({required this.entry, required this.onDelete});

  @override
  State<_HistoryDetailBody> createState() => _HistoryDetailBodyState();
}

class _HistoryDetailBodyState extends State<_HistoryDetailBody> {
  final _fmtDate = DateFormat('MMM d, yyyy – h:mm a');
  final _fmtPct = NumberFormat('##0.0#');

  Map<String, dynamic> get _inputs =>
      widget.entry['inputs'] as Map<String, dynamic>;
  Map<String, dynamic> get _results =>
      widget.entry['results'] as Map<String, dynamic>;

  double get _homeValue => (_inputs['homeValue'] as num).toDouble();
  double get _balance => (_inputs['balance'] as num).toDouble();
  double get _draw => (_inputs['draw'] as num).toDouble();
  double get _rate => (_inputs['rate'] as num).toDouble();
  int get _drawYears => (_inputs['drawYears'] as num).toInt();
  int get _repayYears => (_inputs['repayYears'] as num).toInt();
  double get _equity => (_results['equity'] as num).toDouble();
  double get _ltv => (_results['ltv'] as num).toDouble();
  double get _interestOnly => (_results['interestOnly'] as num).toDouble();
  double get _repayment => (_results['repayment'] as num).toDouble();

  /// Total interest computed from stored inputs (not saved to DB separately).
  double get _totalInterest {
    final stored = _results['totalInterest'];
    if (stored != null) return (stored as num).toDouble();
    // Recompute: IO phase interest + repayment phase amortization interest
    final r = _rate / 100 / 12;
    final ioPhaseInterest = _draw * r * _drawYears * 12;
    final repayN = _repayYears * 12;
    final repayPmt = r > 0
        ? _draw * r * pow(1 + r, repayN) / (pow(1 + r, repayN) - 1)
        : _draw / repayN;
    final repayPhaseInterest = repayPmt * repayN - _draw;
    return ioPhaseInterest + repayPhaseInterest;
  }

  /// Tax savings: stored if available, else estimated at 22%
  double get _taxSavings {
    final stored = _results['taxSavings'];
    if (stored != null) return (stored as num).toDouble();
    return _draw * (_rate / 100) * 0.22;
  }

  DateTime get _createdAt =>
      DateTime.parse(widget.entry['created_at'] as String);

  // ── Share ─────────────────────────────────────────────────────────────────

  Future<void> _share(BuildContext context, bool isEs) async {
    final text = _buildShareText(isEs);
    Share.share(text);
    AnalyticsService.instance.logHistorySaved();
  }

  String _buildShareText(bool isEs) {
    if (isEs) {
      return '''
HELOC Calculator — Resultado

Valor vivienda: ${AmountFormatter.ui(_homeValue, 'USD')}
Saldo hipoteca: ${AmountFormatter.ui(_balance, 'USD')}
Monto dispuesto: ${AmountFormatter.ui(_draw, 'USD')}
Tasa HELOC: ${_rate.toStringAsFixed(2)}%
Período: ${_drawYears}a disposición / ${_repayYears}a pago

Pago solo interés: ${AmountFormatter.ui(_interestOnly, 'USD')}/mes
Pago amortizado: ${AmountFormatter.ui(_repayment, 'USD')}/mes
Capital disponible: ${AmountFormatter.ui(_equity, 'USD')}
LTV actual: ${_fmtPct.format(_ltv)}%
Ahorro fiscal estimado: ${AmountFormatter.ui(_taxSavings, 'USD')}/año

⚠ Consulta a un asesor fiscal. Los intereses del HELOC pueden ser deducibles si se usan para mejoras del hogar.
Calculado el: ${_fmtDate.format(_createdAt.toLocal())}
''';
    }
    return '''
HELOC Calculator — Results

Home Value: ${AmountFormatter.ui(_homeValue, 'USD')}
Mortgage Balance: ${AmountFormatter.ui(_balance, 'USD')}
Draw Amount: ${AmountFormatter.ui(_draw, 'USD')}
HELOC Rate: ${_rate.toStringAsFixed(2)}%
Period: ${_drawYears}yr draw / ${_repayYears}yr repayment

Interest-Only Payment: ${AmountFormatter.ui(_interestOnly, 'USD')}/mo
Repayment Payment: ${AmountFormatter.ui(_repayment, 'USD')}/mo
Available Equity: ${AmountFormatter.ui(_equity, 'USD')}
Current LTV: ${_fmtPct.format(_ltv)}%
Est. Tax Savings: ${AmountFormatter.ui(_taxSavings, 'USD')}/yr

⚠ Consult a tax advisor. HELOC interest may be deductible if used for home improvements.
Calculated: ${_fmtDate.format(_createdAt.toLocal())}
''';
  }

  // ── PDF ──────────────────────────────────────────────────────────────────

  Future<void> _exportPdf(BuildContext context, bool isEs) async {
    if (!freemiumService.hasFullAccess) {
      await PaywallHard.show(context);
      return;
    }
    AnalyticsService.instance.logPdfExported();
    final bytes = await _buildPdf(isEs);
    if (!mounted) return;
    await Printing.sharePdf(
      bytes: bytes,
      filename:
          'HELOC_Calculator_${DateFormat('yyyyMMdd').format(_createdAt)}.pdf',
    );
  }

  Future<Uint8List> _buildPdf(bool isEs) async {
    final params = _HistoryDetailPdfParams(
      homeValue: _homeValue,
      balance: _balance,
      draw: _draw,
      rate: _rate,
      drawYears: _drawYears,
      repayYears: _repayYears,
      equity: _equity,
      ltv: _ltv,
      interestOnly: _interestOnly,
      repayment: _repayment,
      totalInterest: _totalInterest,
      taxSavings: _taxSavings,
      isEs: isEs,
      createdAtMs: _createdAt.millisecondsSinceEpoch,
    );
    return Isolate.run(() => _buildHistoryDetailPdf(params));
  }



  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete(BuildContext context, bool isEs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEs ? '¿Eliminar entrada?' : 'Delete entry?'),
        content: Text(
          isEs
              ? '¿Eliminar este cálculo del historial?'
              : 'Remove this calculation from history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Builder(
              builder: (ctx) => Text(
                isEs ? 'Eliminar' : 'Delete',
                style: TextStyle(color: Theme.of(ctx).colorScheme.error),
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      widget.onDelete();
      Navigator.pop(context);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isEs, __) {
        final dateStr = _fmtDate.format(_createdAt.toLocal());
        return Scaffold(
          appBar: AppBar(
            title: Text(dateStr,
                style: const TextStyle(fontSize: AppTextSize.body)),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded),
                tooltip: isEs ? 'Compartir' : 'Share',
                onPressed: () => _share(context, isEs),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
                tooltip: isEs ? 'Eliminar' : 'Delete',
                onPressed: () => _confirmDelete(context, isEs),
              ),
            ],
          ),
          body: CalcwisePageEntrance(
              child: SafeArea(
            top: false,
            left: false,
            right: false,
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Inputs card ─────────────────────────────────────
                        _SectionHeader(
                          icon: Icons.input_rounded,
                          title: isEs ? 'Datos de Entrada' : 'Input Parameters',
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(children: [
                              _DetailRow(
                                label: isEs
                                    ? 'Valor de la vivienda'
                                    : 'Home Value',
                                value: AmountFormatter.ui(_homeValue, 'USD'),
                                valueColor: AppTheme.primary,
                                bold: true,
                              ),
                              const Divider(height: 16),
                              _DetailRow(
                                label: isEs
                                    ? 'Saldo hipotecario'
                                    : 'Mortgage Balance',
                                value: AmountFormatter.ui(_balance, 'USD'),
                              ),
                              _DetailRow(
                                label:
                                    isEs ? 'Monto a disponer' : 'Draw Amount',
                                value: AmountFormatter.ui(_draw, 'USD'),
                              ),
                              _DetailRow(
                                label: isEs ? 'Tasa HELOC' : 'HELOC Rate',
                                value: '${_rate.toStringAsFixed(2)}%',
                              ),
                              _DetailRow(
                                label: isEs
                                    ? 'Período de disposición'
                                    : 'Draw Period',
                                value: isEs
                                    ? '$_drawYears años'
                                    : '$_drawYears yr',
                              ),
                              _DetailRow(
                                label: isEs
                                    ? 'Período de pago'
                                    : 'Repayment Period',
                                value: isEs
                                    ? '$_repayYears años'
                                    : '$_repayYears yr',
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Results card ────────────────────────────────────
                        _SectionHeader(
                          icon: Icons.bar_chart_rounded,
                          title: isEs ? 'Resultados' : 'Results',
                        ),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(AppSpacing.lg),
                            child: Column(children: [
                              _DetailRow(
                                label: isEs
                                    ? 'Pago mensual (solo interés)'
                                    : 'Monthly IO Payment',
                                value: '${AmountFormatter.ui(_interestOnly, 'USD')}/mo',
                                valueColor: AppTheme.primary,
                                bold: true,
                              ),
                              const Divider(height: 16),
                              _DetailRow(
                                label: isEs
                                    ? 'Pago mensual amortizado'
                                    : 'Monthly Amortizing Payment',
                                value: '${AmountFormatter.ui(_repayment, 'USD')}/mo',
                              ),
                              _DetailRow(
                                label: isEs
                                    ? 'Interés total estimado'
                                    : 'Total Interest',
                                value: AmountFormatter.ui(_totalInterest, 'USD'),
                                valueColor: AppTheme.errorDark,
                              ),
                              _DetailRow(
                                label: isEs
                                    ? 'Capital disponible'
                                    : 'Available Equity',
                                value: AmountFormatter.ui(_equity, 'USD'),
                                valueColor: AppTheme.success,
                              ),
                              _DetailRow(
                                label: 'LTV',
                                value: '${_fmtPct.format(_ltv)}%',
                                valueColor: _ltv > 85 ? Theme.of(context).colorScheme.error : null,
                              ),
                              _DetailRow(
                                label: isEs
                                    ? 'Ahorro fiscal est. (22%)'
                                    : 'Est. Tax Savings (22%)',
                                value: '${AmountFormatter.ui(_taxSavings, 'USD')}/yr',
                                valueColor: Theme.of(context).colorScheme.primary,
                              ),
                            ]),
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Tax info banner
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primaryContainer,
                            borderRadius:
                                BorderRadius.circular(AppRadius.mdPlus),
                            border: Border.all(color: Theme.of(context).colorScheme.primaryContainer),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded,
                                  color: Theme.of(context).colorScheme.primary, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  isEs
                                      ? 'Los intereses del HELOC pueden ser deducibles de impuestos si se usan para mejoras del hogar. Consulta a un asesor fiscal.'
                                      : 'HELOC interest may be tax-deductible if used for home improvements. Consult a tax advisor.',
                                  style: TextStyle(
                                    fontSize: AppTextSize.xs,
                                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.listBottomInset),
                      ],
                    ),
                  ),
                ),
                ValueListenableBuilder<bool>(
                  valueListenable: freemiumService.hasFullAccessNotifier,
                  builder: (_, isPremium, __) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: isPremium
                                  ? AppTheme.primary
                                  : CalcwiseTheme.of(context).surfaceHigh,
                              foregroundColor: isPremium
                                  ? Colors.white
                                  : CalcwiseTheme.of(context).textSecondary,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(AppRadius.lg)),
                              side: isPremium
                                  ? BorderSide.none
                                  : BorderSide(
                                      color: CalcwiseTheme.of(context)
                                          .cardBorder),
                            ),
                            icon: Icon(
                              isPremium
                                  ? Icons.picture_as_pdf_rounded
                                  : Icons.lock_rounded,
                              size: 20,
                            ),
                            label: Text(
                              isEs
                                  ? AppStringsES.exportPdf
                                  : AppStringsEN.exportPdf,
                              style: const TextStyle(
                                  fontSize: AppTextSize.body,
                                  fontWeight: FontWeight.w600),
                            ),
                            onPressed: () async {
                              if (!isPremium) {
                                if (context.mounted) {
                                  await PaywallHard.show(context);
                                }
                                return;
                              }
                              if (!context.mounted) return;
                              await _exportPdf(context, isEs);
                            },
                          ),
                        ),
                      ),
                      if (!isPremium) const CalcwiseAdFooter(),
                    ],
                  ),
                ),
              ],
            ),
          )),
        );
      },
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: AppTextSize.bodyMd,
              fontWeight: FontWeight.w600,
              color: AppTheme.primary,
            ),
          ),
        ],
      );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;

  const _DetailRow({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: AppTextSize.md,
                  color: AppTheme.labelGray,
                ),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                fontSize: AppTextSize.md,
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                color: valueColor,
              ),
            ),
          ],
        ),
      );
}
