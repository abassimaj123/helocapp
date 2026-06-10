import 'package:fl_chart/fl_chart.dart';
import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/heloc_engine.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../widgets/save_scenario_button.dart';
import '../core/freemium/iap_service.dart';

class DrawScheduleScreen extends StatefulWidget {
  const DrawScheduleScreen({super.key});

  @override
  State<DrawScheduleScreen> createState() => _DrawScheduleScreenState();
}

class _DrawScheduleScreenState extends State<DrawScheduleScreen>
    with CalcwiseAutoCalcMixin {
  final _drawCtrl = TextEditingController(text: '100000');
  final _rateCtrl = TextEditingController(text: '8.5');
  final _drawYearsCtrl = TextEditingController(text: '10');
  final _repayYearsCtrl = TextEditingController(text: '20');

  List<Map<String, double>>? _schedule;
  double? _draw;
  double? _rate;
  int? _drawYears;
  int? _repayYears;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('draw_schedule');
    // Pre-fill draw amount and rate from the last calculator result.
    final h = helocNotifier.value;
    if (h.creditLimit > 0) {
      _drawCtrl.text = h.creditLimit.toStringAsFixed(0);
    }
    if (h.rate > 0) {
      _rateCtrl.text = h.rate.toStringAsFixed(1);
    }
    for (final c in [
      _drawCtrl,
      _rateCtrl,
      _drawYearsCtrl,
      _repayYearsCtrl,
    ]) {
      c.addListener(() => scheduleCalc(_generate));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _generate();
    });
  }

  @override
  void dispose() {
    _drawCtrl.dispose();
    _rateCtrl.dispose();
    _drawYearsCtrl.dispose();
    _repayYearsCtrl.dispose();
    super.dispose();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  Future<void> _saveScenario(String? label) async {
    if (_schedule == null) return;
    final draw = double.tryParse(_drawCtrl.text.replaceAll(',', '')) ?? 100000;
    final rate = double.tryParse(_rateCtrl.text) ?? 8.5;
    final drawYears = int.tryParse(_drawYearsCtrl.text) ?? 10;
    final repayYears = int.tryParse(_repayYearsCtrl.text) ?? 20;

    final drawPayment = HelocEngine.interestOnlyPayment(draw, rate);
    final repayPayment = HelocEngine.amortizedPayment(draw, rate, repayYears);
    final totalInterest =
        HelocEngine.totalInterestPaid(draw, rate, drawYears, repayYears);
    final totalPaid = totalInterest + draw;

    final hash = ResultHasher.hashMixed({
      'draw': _roundTo(draw, 1000),
      'rate': _roundTo(rate, 0.25),
      'draw_years': drawYears.toDouble(),
      'repay_years': repayYears.toDouble(),
    });

    await smartHistoryService.saveScenario(
      appKey: 'helocapp',
      screenId: 'draw_schedule',
      inputHash: hash,
      l1: {
        'Draw Amount': AmountFormatter.ui(draw, 'USD'),
        'HELOC Rate': '${rate.toStringAsFixed(2)}%',
        'Draw Period': '${drawYears}y',
        'Repay Period': '${repayYears}y',
        'Draw Payment': AmountFormatter.ui(drawPayment, 'USD'),
        'Total Interest': AmountFormatter.ui(totalInterest, 'USD'),
      },
      l2: {
        'inputs': {
          'creditLimit': draw,
          'rate': rate,
          'drawYears': drawYears,
          'repayYears': repayYears,
        },
        'results': {
          'drawPayment': drawPayment,
          'repayPayment': repayPayment,
          'totalInterest': totalInterest,
          'totalPaid': totalPaid,
        },
      },
      label: label ??
          'Draw Schedule \$${(draw / 1000).toStringAsFixed(0)}k @ ${rate.toStringAsFixed(1)}%',
    );
  }

  Future<void> _generate({bool isManual = false}) async {
    final draw = double.tryParse(_drawCtrl.text.replaceAll(',', '')) ?? 100000;
    final rate = double.tryParse(_rateCtrl.text) ?? 8.5;
    final drawYears = int.tryParse(_drawYearsCtrl.text) ?? 10;
    final repayYears = int.tryParse(_repayYearsCtrl.text) ?? 20;

    setState(() {
      _draw = draw;
      _rate = rate;
      _drawYears = drawYears;
      _repayYears = repayYears;
      _schedule = HelocEngine.drawSchedule(
        drawAmount: draw,
        annualRate: rate,
        drawYears: drawYears,
        repayYears: repayYears,
      );
    });

    AnalyticsService.instance.logDrawScheduleViewed();
    if (isManual) {
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
    }
  }

  Future<void> _exportPdf(BuildContext context, bool isSpanish) async {
    if (!freemiumService.hasFullAccess && !freemiumService.isRewarded) return;
    final doc = pw.Document();
    final schedule = _schedule!;
    final draw = _draw!;
    final rate = _rate!;
    final drawYears = _drawYears!;
    final repayYears = _repayYears!;
    final now = DateTime.now();
    final dateFmt = DateFormat('yyyy-MM-dd HH:mm');

    final title = isSpanish ? 'Calendario HELOC' : 'HELOC Draw Schedule';
    final homeLabel = isSpanish ? 'Monto dispuesto' : 'Draw Amount';
    final creditLabel = isSpanish ? 'Límite de crédito' : 'Credit Limit';
    final drawLabel = isSpanish ? 'Período disposición' : 'Draw Period';
    final repayLabel = isSpanish ? 'Período de pago' : 'Repay Period';
    final rateLabel = isSpanish ? 'Tasa HELOC' : 'HELOC Rate';
    final monthLabel = isSpanish ? 'Mes' : 'Month';
    final balanceLabel = isSpanish ? 'Balance' : 'Balance';
    final interestLabel = isSpanish ? 'Pago interés' : 'Interest Payment';
    final principalLabel = isSpanish ? 'Principal' : 'Principal';
    final remainingLabel = isSpanish ? 'Restante' : 'Remaining';
    final footerLabel = isSpanish
        ? 'Generado: ${dateFmt.format(now)}'
        : 'Generated: ${dateFmt.format(now)}';

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (ctx) => [
          pw.Text(title,
              style: pw.TextStyle(
                  fontSize: AppTextSize.title, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 12),
          pw.Text('$homeLabel: ${AmountFormatter.ui(draw, 'USD')}'),
          pw.Text('$creditLabel: ${AmountFormatter.ui(draw, 'USD')}'),
          pw.Text('$drawLabel: ${drawYears}y'),
          pw.Text('$repayLabel: ${repayYears}y'),
          pw.Text('$rateLabel: ${rate.toStringAsFixed(2)}%'),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              monthLabel,
              balanceLabel,
              interestLabel,
              principalLabel,
              remainingLabel
            ],
            data: schedule.map((row) {
              final month = row['month']!.toInt();
              final balance = row['balance'] ?? 0.0;
              final payment = row['payment'] ?? 0.0;
              final isDrawPhase = (row['type'] ?? 0) == 0;
              final interest =
                  isDrawPhase ? payment : (balance * (rate / 100 / 12));
              final principal = isDrawPhase
                  ? 0.0
                  : (payment - interest).clamp(0.0, double.infinity);
              final remaining =
                  (balance - principal).clamp(0.0, double.infinity);
              return [
                '$month',
                AmountFormatter.ui(balance, 'USD'),
                AmountFormatter.ui(interest, 'USD'),
                AmountFormatter.ui(principal, 'USD'),
                AmountFormatter.ui(remaining, 'USD'),
              ];
            }).toList(),
            headerStyle:
                pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellAlignment: pw.Alignment.centerRight,
            headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
          ),
          pw.SizedBox(height: 12),
          pw.Text(footerLabel,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey)),
        ],
      ),
    );

    await Printing.layoutPdf(onLayout: (_) => doc.save());
    AnalyticsService.instance.logPdfExported();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return CalcwisePageEntrance(
        child: Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEs ? 'Parámetros del HELOC' : 'HELOC Parameters',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: AppTextSize.bodyLg),
                ),
                const SizedBox(height: 14),
                _buildField(
                    _drawCtrl,
                    isEs ? 'Monto dispuesto (\$)' : 'Draw Amount (\$)',
                    '100000'),
                const SizedBox(height: 12),
                _buildField(_rateCtrl,
                    isEs ? 'Tasa HELOC (%)' : 'HELOC Rate (%)', '8.5'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: _buildField(
                        _drawYearsCtrl,
                        isEs ? 'Disposición (años)' : 'Draw Period (yrs)',
                        '10'),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildField(_repayYearsCtrl,
                        isEs ? 'Pago (años)' : 'Repay Period (yrs)', '20'),
                  ),
                ]),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _generate(isManual: true),
                  icon: const Icon(Icons.timeline),
                  label:
                      Text(isEs ? 'Generar calendario' : 'Generate Schedule'),
                ),
                if (_schedule != null) ...[
                  const SizedBox(height: 24),

                  // First 12 months table — always free
                  Text(
                    isEs ? 'Primeros 12 meses' : 'First 12 Months',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyLg),
                  ),
                  const SizedBox(height: 8),
                  _buildTable(isEs, _schedule!.take(12).toList()),

                  const SizedBox(height: 20),

                  // Premium: full schedule, chart, rate scenarios, PDF
                  ValueListenableBuilder<bool>(
                    valueListenable: freemiumService.hasFullAccessNotifier,
                    builder: (_, isPremium, __) {
                      final hasAccess = isPremium || freemiumService.isRewarded;
                      if (!hasAccess) {
                        return CalcwisePremiumGate(
                          title: isEs
                              ? 'Calendario completo, gráfico y PDF'
                              : 'Full Schedule, Chart & PDF Export',
                          description: isEs
                              ? 'Accede al calendario completo, gráfico de balance y exportación PDF.'
                              : 'Access the full amortization schedule, balance chart, and PDF export.',
                          onUnlock: () => IAPService.instance.buy(),
                          price: IAPService.instance.localizedPrice,
                        );
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Balance chart
                          _buildChart(isEs),
                          const SizedBox(height: 20),

                          // Rate scenarios
                          _buildRateScenarios(isEs),
                          const SizedBox(height: 20),

                          // Full schedule beyond 12 months
                          if (_schedule!.length > 12) ...[
                            Text(
                              isEs ? 'Calendario completo' : 'Full Schedule',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTextSize.bodyLg),
                            ),
                            const SizedBox(height: 8),
                            _buildTable(isEs, _schedule!.skip(12).toList()),
                            const SizedBox(height: 20),
                          ],

                          // PDF export
                          OutlinedButton.icon(
                            onPressed: () => _exportPdf(context, isEs),
                            icon: const Icon(Icons.picture_as_pdf_rounded),
                            label: Text(isEs
                                ? AppStringsES.exportPdf
                                : AppStringsEN.exportPdf),
                          ),
                          const SizedBox(height: 12),

                          // Save scenario
                          SaveScenarioButton(onSave: _saveScenario),
                        ],
                      );
                    },
                  ),
                ],
                const SizedBox(height: AppSpacing.listBottomInset),
              ],
            ),
          ),
        ),
        const CalcwiseAdFooter(),
      ],
    ));
  }

  Widget _buildChart(bool isEs) {
    if (_schedule == null) return const SizedBox.shrink();

    // Sample every 6 months for chart readability
    final spots = <FlSpot>[];
    for (int i = 0; i < _schedule!.length; i += 6) {
      final row = _schedule![i];
      spots.add(FlSpot(row['month']!, row['balance']!));
    }
    // Ensure last point
    if (_schedule!.isNotEmpty) {
      final last = _schedule!.last;
      if (spots.isEmpty || spots.last.x != last['month']) {
        spots.add(FlSpot(last['month']!, last['balance']!));
      }
    }

    // Draw period end marker
    final drawEndMonth = (_drawYears! * 12).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEs
                  ? 'Balance del HELOC a lo largo del tiempo'
                  : 'HELOC Balance Over Time',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: AppTextSize.bodyMd),
            ),
            const SizedBox(height: 6),
            Row(children: [
              _LegendDot(color: AppTheme.primary),
              const SizedBox(width: 4),
              Text(isEs ? 'Período disposición' : 'Draw Period',
                  style: const TextStyle(fontSize: AppTextSize.xs)),
              const SizedBox(width: 16),
              _LegendDot(color: AppTheme.success),
              const SizedBox(width: 4),
              Text(isEs ? 'Período de pago' : 'Repayment',
                  style: const TextStyle(fontSize: AppTextSize.xs)),
            ]),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final chartHeight =
                    (constraints.maxWidth < 400) ? 200.0 : 240.0;
                return SizedBox(
                  height: chartHeight,
                  child: LineChart(
                    LineChartData(
                      lineTouchData: LineTouchData(
                        enabled: true,
                        handleBuiltInTouches: true,
                        touchTooltipData: LineTouchTooltipData(
                          getTooltipColor: (_) =>
                              Theme.of(context).colorScheme.inverseSurface,
                          getTooltipItems: (spots) => spots
                              .map((s) => LineTooltipItem(
                                    '\$${(s.y / 1000).toStringAsFixed(1)}k',
                                    TextStyle(
                                        color: Theme.of(context).colorScheme.onInverseSurface,
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppTextSize.sm),
                                  ))
                              .toList(),
                        ),
                      ),
                      gridData: FlGridData(
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: CalcwiseTheme.of(context).cardBorder,
                            strokeWidth: 1),
                      ),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 60,
                            getTitlesWidget: (v, _) => Text(
                              '\$${(v / 1000).toStringAsFixed(0)}k',
                              style: const TextStyle(
                                  fontSize: AppTextSize.xxs, color: AppTheme.labelGray),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 60,
                            getTitlesWidget: (v, _) => Text(
                              '${v ~/ 12}y',
                              style: const TextStyle(
                                  fontSize: AppTextSize.xxs, color: AppTheme.labelGray),
                            ),
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      borderData: FlBorderData(show: false),
                      extraLinesData: ExtraLinesData(verticalLines: [
                        VerticalLine(
                          x: drawEndMonth,
                          color: Colors.orange.withValues(alpha: 0.6),
                          strokeWidth: 1.5,
                          dashArray: [5, 4],
                          label: VerticalLineLabel(
                            show: true,
                            labelResolver: (_) =>
                                isEs ? 'Fin disposición' : 'Draw End',
                            style: const TextStyle(
                                fontSize: AppTextSize.xxs, color: Colors.orange),
                          ),
                        ),
                      ]),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: AppTheme.primary,
                          barWidth: 2.5,
                          dotData: const FlDotData(show: false),
                          belowBarData: BarAreaData(
                            show: true,
                            color: AppTheme.primary.withValues(alpha: 0.08),
                          ),
                        ),
                      ],
                    ),
                    duration: CalcwiseChartTokens.swapDuration,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRateScenarios(bool isEs) {
    final draw = _draw!;
    final baseRate = _rate!;
    final drawYears = _drawYears!;
    final repayYears = _repayYears!;

    final baseInterestOnly = HelocEngine.interestOnlyPayment(draw, baseRate);
    final base1InterestOnly =
        HelocEngine.interestOnlyPayment(draw, baseRate + 1);
    final base2InterestOnly =
        HelocEngine.interestOnlyPayment(draw, baseRate + 2);

    final baseRepay = HelocEngine.amortizedPayment(draw, baseRate, repayYears);
    final base1Repay =
        HelocEngine.amortizedPayment(draw, baseRate + 1, repayYears);
    final base2Repay =
        HelocEngine.amortizedPayment(draw, baseRate + 2, repayYears);

    final baseTotal =
        HelocEngine.totalInterestPaid(draw, baseRate, drawYears, repayYears);
    final base1Total = HelocEngine.totalInterestPaid(
        draw, baseRate + 1, drawYears, repayYears);
    final base2Total = HelocEngine.totalInterestPaid(
        draw, baseRate + 2, drawYears, repayYears);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.compare_arrows, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(
                isEs ? 'Escenarios de tasa' : 'Rate Scenarios',
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: AppTextSize.bodyMd),
              ),
            ]),
            const SizedBox(height: 12),
            Table(
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(2),
                2: FlexColumnWidth(2),
                3: FlexColumnWidth(2),
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.07)),
                  children: [
                    _th(isEs ? 'Tasa' : 'Rate'),
                    _th(isEs ? 'Solo int.' : 'Int. Only'),
                    _th(isEs ? 'Pago' : 'Repay'),
                    _th(isEs ? 'Int. total' : 'Total Int.'),
                  ],
                ),
                _scenarioRow(
                    '${baseRate.toStringAsFixed(1)}%',
                    AmountFormatter.ui(baseInterestOnly, 'USD'),
                    AmountFormatter.ui(baseRepay, 'USD'),
                    AmountFormatter.ui(baseTotal, 'USD'),
                    isBase: true),
                _scenarioRow(
                    '+1% (${(baseRate + 1).toStringAsFixed(1)}%)',
                    AmountFormatter.ui(base1InterestOnly, 'USD'),
                    AmountFormatter.ui(base1Repay, 'USD'),
                    AmountFormatter.ui(base1Total, 'USD')),
                _scenarioRow(
                    '+2% (${(baseRate + 2).toStringAsFixed(1)}%)',
                    AmountFormatter.ui(base2InterestOnly, 'USD'),
                    AmountFormatter.ui(base2Repay, 'USD'),
                    AmountFormatter.ui(base2Total, 'USD')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.xs,
                color: AppTheme.primary)),
      );

  TableRow _scenarioRow(String rate, String io, String repay, String total,
      {bool isBase = false}) {
    final style = TextStyle(
        fontSize: AppTextSize.xs,
        fontWeight: isBase ? FontWeight.bold : FontWeight.normal,
        color: isBase ? AppTheme.primary : null);
    return TableRow(
      children: [rate, io, repay, total]
          .map((t) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Text(t, style: style),
              ))
          .toList(),
    );
  }

  Widget _buildTable(bool isEs, List<Map<String, double>> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Row(children: [
                _tableHeader(isEs ? 'Mes' : 'Month', flex: 1),
                _tableHeader(isEs ? 'Tipo' : 'Type', flex: 2),
                _tableHeader(isEs ? 'Pago' : 'Payment', flex: 2),
                _tableHeader(isEs ? 'Balance' : 'Balance', flex: 2),
              ]),
            ),
            const SizedBox(height: 4),
            ...rows.map((row) {
              final month = row['month']!.toInt();
              final isDrawPhase = row['type'] == 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Row(children: [
                  Expanded(
                      flex: 1,
                      child: Text('$month',
                          style: const TextStyle(fontSize: AppTextSize.sm))),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color:
                            (isDrawPhase ? AppTheme.primary : AppTheme.success)
                                .withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        isDrawPhase
                            ? (isEs ? 'Disposición' : 'Draw')
                            : (isEs ? 'Pago' : 'Repay'),
                        style: TextStyle(
                            fontSize: AppTextSize.xs,
                            color: isDrawPhase
                                ? AppTheme.primary
                                : AppTheme.success,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Expanded(
                      flex: 2,
                      child: Text(AmountFormatter.ui(row['payment']!, 'USD'),
                          style: const TextStyle(fontSize: AppTextSize.sm))),
                  Expanded(
                      flex: 2,
                      child: Text(AmountFormatter.ui(row['balance']!, 'USD'),
                          style: const TextStyle(fontSize: AppTextSize.sm))),
                ]),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(String text, {required int flex}) => Expanded(
        flex: flex,
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.xs,
                color: AppTheme.primary)),
      );

  Widget _buildField(TextEditingController ctrl, String label, String hint) {
    return TextFormField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  const _LegendDot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
