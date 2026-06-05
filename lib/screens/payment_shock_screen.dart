import 'dart:math' show pow;

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../core/freemium/iap_service.dart';

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
  final _currentRateCtrl = TextEditingController(text: '8.5');
  int _repayYears = 20;
  double _projectedRate = 9.5;

  _ShockResult? _result;

  @override
  void initState() {
    super.initState();
    // Pre-fill balance and rate from the last calculator result.
    final h = helocNotifier.value;
    _balanceCtrl.text = h.balance.toStringAsFixed(0);
    _currentRateCtrl.text = h.rate.toStringAsFixed(1);
    for (final c in [_balanceCtrl, _currentRateCtrl]) {
      c.addListener(() => scheduleCalc(_tryCompute));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCompute());
  }

  @override
  void dispose() {
    _balanceCtrl.dispose();
    _currentRateCtrl.dispose();
    super.dispose();
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
    setState(() => _result = _ShockResult(
          ioPayment: io,
          piPayment: pi,
          shockPct: shockPct.toDouble(),
          dollarIncrease: dollarInc,
          totalInterest: totalInterest,
        ));

    if (silent) return;
    adService.onAction();
    AnalyticsService.instance.log('payment_shock_calculated');
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
    _currentRateCtrl.text = '8.5';
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
                      hint: '8.5',
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
                      onPressed: () => _compute(),
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
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.xl)),
                      ),
                      child: Text(isEs ? 'Limpiar' : 'Reset'),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    AnimatedSwitcher(
                      duration: AppDuration.base,
                      child: _result == null
                          ? const SizedBox.shrink()
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
        Card(
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
        const SizedBox(height: AppSpacing.md),

        Row(children: [
          Expanded(
              child: _metricCard(isEs ? 'Choque' : 'Shock',
                  '+${r.shockPct.toStringAsFixed(1)}%', _piColor)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
              child: _metricCard(isEs ? 'Aumento' : 'Increase',
                  '+${AmountFormatter.ui(r.dollarIncrease, 'USD')}', _piColor)),
        ]),
        const SizedBox(height: AppSpacing.md),
        _metricCard(
          isEs
              ? 'Interés total durante el pago'
              : 'Total interest over repayment',
          AmountFormatter.ui(r.totalInterest, 'USD'),
          _ioColor,
        ),

        const SizedBox(height: AppSpacing.xl),

        // Premium: bar chart + full projection
        ValueListenableBuilder<bool>(
          valueListenable: freemiumService.hasFullAccessNotifier,
          builder: (_, isPremium, __) {
            if (!isPremium) {
              return CalcwisePremiumCta(
                feature: isEs
                    ? 'Proyección completa y gráfico'
                    : 'Full Projection & Chart',
                onTap: () => IAPService.instance.buy(),
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
                SizedBox(height: 200, child: _buildBarChart(isEs, r)),
              ],
            );
          },
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
