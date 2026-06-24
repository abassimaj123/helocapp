import 'dart:async';
import 'dart:math' show pow;

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/services/pdf_export_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../core/freemium/iap_service.dart';
import '../widgets/save_scenario_button.dart';
import 'history_screen.dart';

const _ioColor = AppTheme.primary;
const _piColor = Color(0xFFC62828);

double _parseN(String v) {
  if (v.isEmpty) return 0.0;
  final s = (v.contains('.') && v.contains(','))
      ? v.replaceAll(',', '')
      : v.replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

class _ShockResult {
  final double ioPayment;
  final double piPayment;
  final double shockPct;
  final double dollarIncrease;
  final double totalInterest;

  const _ShockResult({
    required this.ioPayment,
    required this.piPayment,
    required this.shockPct,
    required this.dollarIncrease,
    required this.totalInterest,
  });
}

class PaymentShockScreen extends StatefulWidget {
  const PaymentShockScreen({super.key});

  @override
  State<PaymentShockScreen> createState() => _PaymentShockScreenState();
}

class _PaymentShockScreenState extends State<PaymentShockScreen> with CalcwiseAutoCalcMixin {
  final _formKey = GlobalKey<FormState>();

  final _balanceCtrl = TextEditingController(text: '100000');
  final _currentRateCtrl = TextEditingController(text: '7.5');
  int _repayYears = 20;
  double _projectedRate = 9.5;

  _ShockResult? _result;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('payment_shock');
    // Pre-fill balance and rate from the last calculator result.
    final h = helocNotifier.value;
    _balanceCtrl.text = h.balance.toStringAsFixed(0);
    _currentRateCtrl.text = h.rate.toStringAsFixed(1);
    for (final c in [_balanceCtrl, _currentRateCtrl]) {
      c.addListener(() => scheduleCalc(_tryCompute));
    }
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCompute());
  }

  void _onLangChange() => setState(() {});

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    smartHistoryService.cancelPendingSave('helocapp', 'payment_shock');
    _balanceCtrl.dispose();
    _currentRateCtrl.dispose();
    super.dispose();
  }

  double _roundTo(double v, double step) => (v / step).round() * step;

  Map<String, String> _buildL1(_ShockResult r) {
    final isEs = isSpanishNotifier.value;
    return {
      isEs ? 'Pago Solo Interés' : 'IO Payment': AmountFormatter.ui(r.ioPayment, 'USD'),
      isEs ? 'Pago P+I' : 'PI Payment': AmountFormatter.ui(r.piPayment, 'USD'),
      isEs ? 'Choque de Pago' : 'Payment Shock': '${r.shockPct >= 0 ? '+' : ''}${r.shockPct.toStringAsFixed(1)}%',
      isEs ? 'Aumento en Dólares' : 'Dollar Increase': '+${AmountFormatter.ui(r.dollarIncrease, 'USD')}',
      isEs ? 'Interés Total' : 'Total Interest': AmountFormatter.ui(r.totalInterest, 'USD'),
    };
  }

  Map<String, dynamic> _buildL2(_ShockResult r) => {
        'inputs': {
          'balance': _parseN(_balanceCtrl.text),
          'current_rate': _parseN(_currentRateCtrl.text),
          'repay_years': _repayYears,
          'projected_rate': _projectedRate,
        },
        'results': {
          'io_payment': r.ioPayment,
          'pi_payment': r.piPayment,
          'shock_pct': r.shockPct,
          'dollar_increase': r.dollarIncrease,
          'total_interest': r.totalInterest,
        },
      };

  void _scheduleAutoSave(_ShockResult r) {
    final hash = ResultHasher.hashMixed({
      'balance': _roundTo(_parseN(_balanceCtrl.text), 500),
      'current_rate': _roundTo(_parseN(_currentRateCtrl.text), 0.25),
      'projected_rate': _roundTo(_projectedRate, 0.25),
      'repay_years': _repayYears,
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'helocapp',
      screenId: 'payment_shock',
      inputHash: hash,
      l1: _buildL1(r),
      l2: _buildL2(r),
    );
    HistoryScreen.refreshNotifier.value++;
  }

  Future<void> _saveScenario(String? label) async {
    if (_result == null) return;
    final hash = ResultHasher.hashMixed({
      'balance': _roundTo(_parseN(_balanceCtrl.text), 500),
      'current_rate': _roundTo(_parseN(_currentRateCtrl.text), 0.25),
      'projected_rate': _roundTo(_projectedRate, 0.25),
      'repay_years': _repayYears,
    });
    await smartHistoryService.saveScenario(
      appKey: 'helocapp',
      screenId: 'payment_shock',
      inputHash: hash,
      l1: _buildL1(_result!),
      l2: _buildL2(_result!),
      label: label ?? (isSpanishNotifier.value
          ? 'Choque de Pago \$${(_parseN(_balanceCtrl.text) / 1000).toStringAsFixed(0)}k @ ${_projectedRate.toStringAsFixed(1)}%'
          : 'Payment Shock \$${(_parseN(_balanceCtrl.text) / 1000).toStringAsFixed(0)}k @ ${_projectedRate.toStringAsFixed(1)}%'),
    );
    HistoryScreen.refreshNotifier.value++;
    adService.onSave();
  }

  Future<void> _exportPdf() async {
    final r = _result;
    if (r == null) return;
    final isEs = isSpanishNotifier.value;
    Future<void> doExport() => PdfExportService.exportPaymentShock(
          context: context,
          helocBalance: _parseN(_balanceCtrl.text),
          currentRate: _parseN(_currentRateCtrl.text),
          projectedRate: _projectedRate,
          repayYears: _repayYears,
          ioPayment: r.ioPayment,
          piPayment: r.piPayment,
          shockPct: r.shockPct,
          dollarIncrease: r.dollarIncrease,
          totalInterest: r.totalInterest,
          isEs: isEs,
          isFr: false,
        );
    if (freemiumService.hasFullAccess) {
      await doExport();
    } else {
      await PdfExportService.showUnlockOrPay(context, doExport);
    }
    AnalyticsService.instance.logPdfExported();
  }

  void _tryCompute() {
    final balance = _parseN(_balanceCtrl.text);
    final currentRate = _parseN(_currentRateCtrl.text);
    if (balance <= 0 || currentRate <= 0) return;
    _compute(silent: true);
  }

  Future<void> _compute({bool silent = false}) async {
    final balance = _parseN(_balanceCtrl.text);
    final currentRate = _parseN(_currentRateCtrl.text);
    if (balance <= 0 || currentRate <= 0) return;

    final io = balance * (currentRate / 100) / 12;
    final r = (_projectedRate / 100) / 12;
    final n = _repayYears * 12;
    final pi =
        r > 0 ? balance * r * pow(1 + r, n) / (pow(1 + r, n) - 1) : balance / n;
    final shockPct = io > 0 ? (pi - io) / io * 100 : 0.0;
    final dollarInc = pi - io;
    final totalInterest = (pi * n) - balance;

    if (!mounted) return;
    final newResult = _ShockResult(
      ioPayment: io,
      piPayment: pi,
      shockPct: shockPct.toDouble(),
      dollarIncrease: dollarInc,
      totalInterest: totalInterest,
    );
    setState(() => _result = newResult);
    _scheduleAutoSave(newResult);

    if (silent) return;
    adService.onAction();
    AnalyticsService.instance.log('payment_shock_calculated');
    unawaited(AnalyticsService.instance.maybeLogFirstCalculate());
    final trigger = await paywallSession.recordAction();
    if (!mounted) return;
    if (trigger == PaywallTrigger.hard && !freemiumService.hasFullAccess) {
      PaywallHard.show(context);
    } else if (trigger == PaywallTrigger.soft &&
        !freemiumService.hasFullAccess) {
      PaywallSoft.show(context);
    }
  }

  void _reset() {
    _balanceCtrl.text = '100000';
    _currentRateCtrl.text = '7.5';
    setState(() {
      _repayYears = 20;
      _projectedRate = 9.5;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? 'Choque de Pago' : 'Payment Shock'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: CalcwisePageEntrance(
                child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.mdPlus),
                      decoration: BoxDecoration(
                        color: _piColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border:
                            Border.all(color: _piColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: _piColor, size: 18),
                        const SizedBox(width: AppSpacing.smPlus),
                        Expanded(
                          child: Text(
                            isEs
                                ? 'Al final del período de disposición, tu pago puede duplicarse o triplicarse.'
                                : 'When your draw period ends, your payment may double or triple.',
                            style: const TextStyle(
                                fontSize: AppTextSize.sm, color: _piColor),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(isEs
                        ? 'Saldo al final del período'
                        : 'Balance at End of Draw'),
                    const SizedBox(height: AppSpacing.md),
                    _field(
                      ctrl: _balanceCtrl,
                      label: isEs ? 'Saldo (\$)' : 'Balance (\$)',
                      hint: '100000',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _sectionHeader(
                        isEs ? 'Período de pago' : 'Repayment Period'),
                    const SizedBox(height: AppSpacing.sm),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 10, label: Text('10 yr')),
                        ButtonSegment(value: 15, label: Text('15 yr')),
                        ButtonSegment(value: 20, label: Text('20 yr')),
                      ],
                      selected: {_repayYears},
                      onSelectionChanged: (s) {
                        setState(() => _repayYears = s.first);
                        scheduleCalc(_tryCompute);
                      },
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _sectionHeader(isEs ? 'Tasa actual' : 'Current Rate'),
                    const SizedBox(height: AppSpacing.md),
                    _field(
                      ctrl: _currentRateCtrl,
                      label: isEs ? 'Tasa actual (%)' : 'Current Rate (%)',
                      hint: '7.5',
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _sectionHeader(isEs
                        ? 'Tasa proyectada al final'
                        : 'Projected Rate at End of Draw'),
                    const SizedBox(height: AppSpacing.xs),
                    Row(children: [
                      Expanded(
                        child: Slider(
                          value: _projectedRate,
                          min: 3,
                          max: 15,
                          divisions: 120,
                          label: '${_projectedRate.toStringAsFixed(2)}%',
                          onChanged: (v) {
                            setState(() => _projectedRate = v);
                            scheduleCalc(_tryCompute);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 64,
                        child: Text(
                          '${_projectedRate.toStringAsFixed(2)}%',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    ElevatedButton.icon(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _compute();
                      },
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.xl)),
                      ),
                      icon: const Icon(Icons.bolt),
                      label: Text(isEs ? 'Calcular choque' : 'Calculate Shock'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    OutlinedButton(
                      onPressed: () {
                        HapticFeedback.mediumImpact();
                        _reset();
                      },
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.xl)),
                      ),
                      child: Text(isEs ? 'Limpiar' : 'Reset'),
                    ),
                    if (_result != null &&
                        (freemiumService.hasFullAccess ||
                            freemiumService.isRewarded)) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SaveScenarioButton(onSave: _saveScenario),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: () {
                          HapticFeedback.mediumImpact();
                          _exportPdf();
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.xl)),
                        ),
                        icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                        label: Text(isEs ? 'Exportar PDF' : 'Export PDF'),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedSwitcher(
                      duration: AppDuration.base,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: _result == null
                          ? Padding(
                              key: const ValueKey('empty'),
                              padding: const EdgeInsets.only(top: AppSpacing.xl),
                              child: Center(
                                child: Text(
                                  isEs
                                      ? 'Ingresa el saldo y la tasa para ver el impacto'
                                      : 'Enter balance and rate to see the payment impact',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                      color: AppTheme.labelGray,
                                      fontSize: AppTextSize.md),
                                ),
                              ),
                            )
                          : _buildResults(isEs, _result!),
                    ),
                    const SizedBox(height: AppSpacing.listBottomInset),
                  ],
                ),
              ), // Form
              ), // CalcwisePageEntrance
            ),
          ),
          const CalcwiseAdFooter(),
        ],
      ),
    );
  }

  Widget _buildResults(bool isEs, _ShockResult r) {
    return Column(
      key: ValueKey(
          '${r.piPayment.toStringAsFixed(2)}_${r.shockPct.toStringAsFixed(2)}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero
        CalcwiseStaggerItem(
          index: 0,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.xl),
              side: BorderSide(color: _piColor.withValues(alpha: 0.3)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isEs ? 'Nuevo pago mensual' : 'New monthly payment',
                    style: const TextStyle(
                        fontSize: AppTextSize.md, color: AppTheme.labelGray),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AmountFormatter.ui(r.piPayment, 'USD'),
                    style: const TextStyle(
                      fontSize: AppTextSize.hero,
                      fontWeight: FontWeight.bold,
                      color: _piColor,
                      height: 1.0,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.smPlus),
                  Text(
                    isEs
                        ? 'Tu pago pasa de ${AmountFormatter.ui(r.ioPayment, 'USD')}/mes a ${AmountFormatter.ui(r.piPayment, 'USD')}/mes (+${r.shockPct.toStringAsFixed(0)}%)'
                        : 'Your payment goes from ${AmountFormatter.ui(r.ioPayment, 'USD')}/mo to ${AmountFormatter.ui(r.piPayment, 'USD')}/mo (+${r.shockPct.toStringAsFixed(0)}%)',
                    style: const TextStyle(fontSize: AppTextSize.md),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        CalcwiseStaggerItem(
          index: 1,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                    child: _metricCard(isEs ? 'Choque' : 'Shock',
                        '${r.shockPct >= 0 ? '+' : ''}${r.shockPct.toStringAsFixed(1)}%', _piColor)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                    child: _metricCard(isEs ? 'Aumento' : 'Increase',
                        '+${AmountFormatter.ui(r.dollarIncrease, 'USD')}', _piColor)),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        CalcwiseStaggerItem(
          index: 2,
          child: _metricCard(
            isEs
                ? 'Interés total durante el pago'
                : 'Total interest over repayment',
            AmountFormatter.ui(r.totalInterest, 'USD'),
            _ioColor,
          ),
        ),

        const SizedBox(height: AppSpacing.xl),

        // Premium: bar chart + full projection
        CalcwiseStaggerItem(
          index: 3,
          child: ValueListenableBuilder<bool>(
          valueListenable: freemiumService.hasFullAccessNotifier,
          builder: (_, isPremium, __) {
            if (!isPremium) {
              return CalcwisePremiumGate(
                title: isEs
                    ? 'Proyección completa y gráfico'
                    : 'Full Projection & Chart',
                description: isEs
                    ? 'Visualiza la comparación completa de pagos con gráfico interactivo.'
                    : 'View the full payment comparison with an interactive bar chart.',
                onUnlock: () {
                  PaywallHard.show(context);
                },
                price: IAPService.instance.localizedPrice,
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEs ? 'Comparación mensual' : 'Monthly payment comparison',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: AppTextSize.body),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  height: 200,
                  child: CalcwiseChartReveal(
                    child: _buildBarChart(isEs, r),
                  ),
                ),
              ],
            );
          },
        ),
        ),
      ],
    );
  }

  Widget _buildBarChart(bool isEs, _ShockResult r) {
    final cs = Theme.of(context).colorScheme;
    final maxY = (r.piPayment * 1.2);
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => cs.inverseSurface,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final label = group.x == 0
                  ? (isEs ? 'Solo interés' : 'Interest-only')
                  : (isEs ? 'P + I' : 'P + I');
              return BarTooltipItem(
                '$label\n${AmountFormatter.ui(rod.toY, 'USD')}',
                TextStyle(
                  color: cs.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.sm,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, m) => Text(
                '\$${(v / 1000).toStringAsFixed(0)}k',
                style: const TextStyle(
                    fontSize: CalcwiseChartTokens.axisFontSize,
                    color: AppTheme.labelGray),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (v, m) {
                final label = v.toInt() == 0
                    ? (isEs ? 'Solo interés' : 'Interest-only')
                    : (isEs ? 'P + I' : 'P + I');
                return Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(label,
                      style: const TextStyle(fontSize: AppTextSize.xs)),
                );
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: [
          BarChartGroupData(x: 0, barRods: [
            BarChartRodData(
              toY: r.ioPayment,
              color: _ioColor,
              width: CalcwiseChartTokens.barWidth,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ]),
          BarChartGroupData(x: 1, barRods: [
            BarChartRodData(
              toY: r.piPayment,
              color: cs.error,
              width: CalcwiseChartTokens.barWidth,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(6)),
            ),
          ]),
        ],
      ),
      swapAnimationDuration: CalcwiseChartTokens.swapDuration,
    );
  }

  Widget _metricCard(String label, String value, Color color) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: AppTextSize.xs, color: AppTheme.labelGray)),
            const SizedBox(height: 6),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.subtitle,
                    color: color)),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String text) => Text(
        text,
        style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: AppTextSize.bodyMd,
            color: _ioColor),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))
        ],
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
}
