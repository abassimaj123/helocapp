import 'dart:math' show pow;

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';

const _helocColor = AppTheme.primary;
const _refiColor = Color(0xFF01579B);

double _parseN(String v) {
  if (v.isEmpty) return 0.0;
  final s = (v.contains('.') && v.contains(','))
      ? v.replaceAll(',', '')
      : v.replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

double _amortizedPayment(double balance, double annualRatePct, int years) {
  if (balance <= 0 || years <= 0) return 0;
  final r = annualRatePct / 100 / 12;
  final n = years * 12;
  if (r == 0) return balance / n;
  return balance * r * pow(1 + r, n) / (pow(1 + r, n) - 1);
}

double _totalInterestAmort(double balance, double annualRatePct, int years) {
  final p = _amortizedPayment(balance, annualRatePct, years);
  return (p * years * 12) - balance;
}

class _CompareCashoutResult {
  // HELOC scenario
  final double existingMortgagePI;
  final double helocIO;
  final double helocPI;
  final double scenarioATotalMonthly;
  final double scenarioATotalInterest30y;

  // Cash-out refi scenario
  final double refiNewBalance;
  final double refiMonthly;
  final double refiClosingCosts;
  final double scenarioBTotalInterest30y;
  final double scenarioBTotalCost;

  final int
      breakevenMonths; // months until cumulative HELOC cost exceeds refi cost
  final int winnerIndex; // 0 = HELOC, 1 = Refi

  const _CompareCashoutResult({
    required this.existingMortgagePI,
    required this.helocIO,
    required this.helocPI,
    required this.scenarioATotalMonthly,
    required this.scenarioATotalInterest30y,
    required this.refiNewBalance,
    required this.refiMonthly,
    required this.refiClosingCosts,
    required this.scenarioBTotalInterest30y,
    required this.scenarioBTotalCost,
    required this.breakevenMonths,
    required this.winnerIndex,
  });
}

class HelocVsCashoutScreen extends StatefulWidget {
  const HelocVsCashoutScreen({super.key});

  @override
  State<HelocVsCashoutScreen> createState() => _HelocVsCashoutScreenState();
}

class _HelocVsCashoutScreenState extends State<HelocVsCashoutScreen> with CalcwiseAutoCalcMixin {
  final _formKey = GlobalKey<FormState>();

  final _homeValueCtrl = TextEditingController(text: '500000');
  final _existingBalCtrl = TextEditingController(text: '250000');
  final _existingRateCtrl = TextEditingController(text: '4.0');
  final _existingYearsCtrl = TextEditingController(text: '25');
  final _cashCtrl = TextEditingController(text: '75000');
  final _helocRateCtrl = TextEditingController(text: '8.5');
  final _refiRateCtrl = TextEditingController(text: '6.5');
  final _closingPctCtrl = TextEditingController(text: '3');

  bool _financeClosing = true;

  _CompareCashoutResult? _result;

  @override
  void initState() {
    super.initState();
    // Pre-fill balance and rate from the last calculator result.
    final h = helocNotifier.value;
    _existingBalCtrl.text = h.balance.toStringAsFixed(0);
    _helocRateCtrl.text = h.rate.toStringAsFixed(1);
    for (final c in [
      _homeValueCtrl,
      _existingBalCtrl,
      _existingRateCtrl,
      _existingYearsCtrl,
      _cashCtrl,
      _helocRateCtrl,
      _refiRateCtrl,
      _closingPctCtrl,
    ]) {
      c.addListener(() => scheduleCalc(_tryCompute));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCompute());
  }

  @override
  void dispose() {
    for (final c in [
      _homeValueCtrl,
      _existingBalCtrl,
      _existingRateCtrl,
      _existingYearsCtrl,
      _cashCtrl,
      _helocRateCtrl,
      _refiRateCtrl,
      _closingPctCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _tryCompute() {
    final existingBal = _parseN(_existingBalCtrl.text);
    final existingRate = _parseN(_existingRateCtrl.text);
    final existingYears = int.tryParse(_existingYearsCtrl.text) ?? 0;
    final cash = _parseN(_cashCtrl.text);
    final helocRate = _parseN(_helocRateCtrl.text);
    final refiRate = _parseN(_refiRateCtrl.text);
    if (existingBal <= 0 ||
        existingRate <= 0 ||
        existingYears <= 0 ||
        cash <= 0 ||
        helocRate <= 0 ||
        refiRate <= 0) {
      return;
    }
    _compute(silent: true);
  }

  Future<void> _compute({bool silent = false}) async {
    final existingBal = _parseN(_existingBalCtrl.text);
    final existingRate = _parseN(_existingRateCtrl.text);
    final existingYears = int.tryParse(_existingYearsCtrl.text) ?? 0;
    final cash = _parseN(_cashCtrl.text);
    final helocRate = _parseN(_helocRateCtrl.text);
    final refiRate = _parseN(_refiRateCtrl.text);
    final closingPct = _parseN(_closingPctCtrl.text);
    if (existingBal <= 0 ||
        existingRate <= 0 ||
        existingYears <= 0 ||
        cash <= 0) return;

    // Scenario A — HELOC
    final existingPI =
        _amortizedPayment(existingBal, existingRate, existingYears);
    final helocIO = cash * (helocRate / 100) / 12;
    final helocPI = _amortizedPayment(cash, helocRate, 20);
    final aMonthly = existingPI + helocIO;
    // Total interest 30y: existing mortgage interest + heloc IO (10y) + heloc P&I (20y)
    final existingTotalInt =
        _totalInterestAmort(existingBal, existingRate, existingYears);
    final helocIOTotal = helocIO * 12 * 10;
    final helocPITotal = (helocPI * 12 * 20) - cash;
    final aTotalInterest = existingTotalInt + helocIOTotal + helocPITotal;

    // Scenario B — Cash-Out Refi
    final closingCosts = (existingBal + cash) * (closingPct / 100);
    final refiPrincipal =
        existingBal + cash + (_financeClosing ? closingCosts : 0);
    final refiMonthly = _amortizedPayment(refiPrincipal, refiRate, 30);
    final refiTotalInterest = _totalInterestAmort(refiPrincipal, refiRate, 30);
    final bTotalCost = refiTotalInterest + (_financeClosing ? 0 : closingCosts);

    // Breakeven: cumulative scenario A cost vs scenario B cost over months
    // Approximate by total monthly outflow + upfront costs
    const aUpfront = 0.0;
    final bUpfront = _financeClosing ? 0.0 : closingCosts;
    int breakeven = 9999;
    double aCum = aUpfront;
    double bCum = bUpfront;
    // Use IO for first 120 months on A, then PI; B is constant
    for (int m = 1; m <= 360; m++) {
      final aPay = existingPI + (m <= 120 ? helocIO : helocPI);
      aCum += aPay;
      bCum += refiMonthly;
      if (aCum >= bCum && breakeven == 9999) {
        breakeven = m;
        break;
      }
    }

    final aTotal = aTotalInterest;
    final bTotal = bTotalCost;
    final winner = aTotal <= bTotal ? 0 : 1;

    if (!mounted) return;
    setState(() => _result = _CompareCashoutResult(
          existingMortgagePI: existingPI,
          helocIO: helocIO,
          helocPI: helocPI,
          scenarioATotalMonthly: aMonthly,
          scenarioATotalInterest30y: aTotalInterest,
          refiNewBalance: refiPrincipal,
          refiMonthly: refiMonthly,
          refiClosingCosts: closingCosts,
          scenarioBTotalInterest30y: refiTotalInterest,
          scenarioBTotalCost: bTotalCost,
          breakevenMonths: breakeven,
          winnerIndex: winner,
        ));

    if (silent) return;
    adService.onAction();
    AnalyticsService.instance.log('heloc_vs_cashout_calculated');
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
    _homeValueCtrl.text = '500000';
    _existingBalCtrl.text = '250000';
    _existingRateCtrl.text = '4.0';
    _existingYearsCtrl.text = '25';
    _cashCtrl.text = '75000';
    _helocRateCtrl.text = '8.5';
    _refiRateCtrl.text = '6.5';
    _closingPctCtrl.text = '3';
    setState(() {
      _financeClosing = true;
      _result = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(isEs ? 'HELOC vs Refi con Retiro' : 'HELOC vs Cash-Out Refi'),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.mdPlus),
                      decoration: BoxDecoration(
                        color: _helocColor.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(
                            color: _helocColor.withValues(alpha: 0.2)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.info_outline,
                            color: _helocColor, size: 18),
                        const SizedBox(width: AppSpacing.smPlus),
                        Expanded(
                          child: Text(
                            isEs
                                ? 'Compara: mantener tu hipoteca + un HELOC, vs refinanciar todo con retiro de efectivo.'
                                : 'Compare: keep your mortgage + add a HELOC, vs refinance everything with cash out.',
                            style: const TextStyle(
                                fontSize: AppTextSize.sm, color: _helocColor),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(isEs ? 'Vivienda' : 'Home'),
                    const SizedBox(height: AppSpacing.md),
                    _field(
                        ctrl: _homeValueCtrl,
                        label: isEs
                            ? 'Valor de la vivienda (\$)'
                            : 'Home value (\$)',
                        hint: '500000'),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(
                        isEs ? 'Hipoteca existente' : 'Existing mortgage'),
                    const SizedBox(height: AppSpacing.md),
                    _field(
                        ctrl: _existingBalCtrl,
                        label: isEs ? 'Saldo (\$)' : 'Balance (\$)',
                        hint: '250000'),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                          child: _field(
                              ctrl: _existingRateCtrl,
                              label: isEs ? 'Tasa (%)' : 'Rate (%)',
                              hint: '4.0')),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: _field(
                              ctrl: _existingYearsCtrl,
                              label: isEs ? 'Años restantes' : 'Years left',
                              hint: '25',
                              intOnly: true)),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(isEs ? 'Efectivo necesario' : 'Cash needed'),
                    const SizedBox(height: AppSpacing.md),
                    _field(
                        ctrl: _cashCtrl,
                        label: isEs ? 'Monto (\$)' : 'Amount (\$)',
                        hint: '75000'),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(isEs ? 'Tasas' : 'Rates', color: _refiColor),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                          child: _field(
                              ctrl: _helocRateCtrl,
                              label: isEs ? 'Tasa HELOC (%)' : 'HELOC rate (%)',
                              hint: '8.5')),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                          child: _field(
                              ctrl: _refiRateCtrl,
                              label: isEs ? 'Tasa Refi (%)' : 'Refi rate (%)',
                              hint: '6.5')),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(
                        isEs ? 'Costos de cierre Refi' : 'Refi closing costs',
                        color: _refiColor),
                    const SizedBox(height: AppSpacing.md),
                    _field(
                        ctrl: _closingPctCtrl,
                        label: isEs ? 'Porcentaje (%)' : 'Percent (%)',
                        hint: '3'),
                    const SizedBox(height: AppSpacing.sm),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        isEs
                            ? 'Financiar costos de cierre'
                            : 'Finance closing costs',
                        style: const TextStyle(fontSize: AppTextSize.body),
                      ),
                      value: _financeClosing,
                      onChanged: (v) => setState(() {
                        _financeClosing = v;
                        _tryCompute();
                      }),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    ElevatedButton.icon(
                      onPressed: () => _compute(),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 52),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.xl)),
                      ),
                      icon: const Icon(Icons.compare_arrows),
                      label: Text(isEs ? 'Comparar' : 'Compare'),
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
              ),
            ),
          ),
          const CalcwiseAdFooter(),
        ],
      ),
    );
  }

  Widget _buildResults(bool isEs, _CompareCashoutResult r) {
    return Column(
      key: ValueKey(
          '${r.scenarioATotalMonthly.toStringAsFixed(2)}_${r.refiMonthly.toStringAsFixed(2)}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Winner banner
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: r.winnerIndex == 0 ? _helocColor : _refiColor,
            borderRadius: BorderRadius.circular(AppRadius.xl),
          ),
          child: Row(children: [
            const Icon(Icons.emoji_events_rounded,
                color: Colors.white, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                isEs
                    ? (r.winnerIndex == 0
                        ? 'Mejor opción: HELOC'
                        : 'Mejor opción: Refi con Retiro')
                    : (r.winnerIndex == 0
                        ? 'Best option: HELOC'
                        : 'Best option: Cash-Out Refi'),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: AppTextSize.bodyMd),
              ),
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),

        ComparisonView(
          title: isEs ? 'Comparación' : 'Comparison',
          winnerIndex: r.winnerIndex,
          scenarios: [
            ComparisonScenario(
              label: 'HELOC',
              accentColor: _helocColor,
              metrics: {
                (isEs ? 'Pago mensual inicial' : 'Initial monthly'):
                    AmountFormatter.ui(r.scenarioATotalMonthly, 'USD'),
                (isEs ? 'Pago mensual (fase pago)' : 'Monthly (repay phase)'):
                    AmountFormatter.ui(r.existingMortgagePI + r.helocPI, 'USD'),
                (isEs ? 'Costos iniciales' : 'Upfront costs'): r'$0',
                (isEs ? 'Interés total 30 años' : 'Total interest 30y'):
                    AmountFormatter.ui(r.scenarioATotalInterest30y, 'USD'),
                (isEs ? 'Costo total' : 'Total cost'):
                    AmountFormatter.ui(r.scenarioATotalInterest30y, 'USD'),
              },
            ),
            ComparisonScenario(
              label: isEs ? 'Refi con Retiro' : 'Cash-Out Refi',
              accentColor: _refiColor,
              metrics: {
                (isEs ? 'Pago mensual inicial' : 'Initial monthly'):
                    AmountFormatter.ui(r.refiMonthly, 'USD'),
                (isEs ? 'Pago mensual (fase pago)' : 'Monthly (repay phase)'):
                    AmountFormatter.ui(r.refiMonthly, 'USD'),
                (isEs ? 'Costos iniciales' : 'Upfront costs'):
                    _financeClosing ? r'$0' : AmountFormatter.ui(r.refiClosingCosts, 'USD'),
                (isEs ? 'Interés total 30 años' : 'Total interest 30y'):
                    AmountFormatter.ui(r.scenarioBTotalInterest30y, 'USD'),
                (isEs ? 'Costo total' : 'Total cost'):
                    AmountFormatter.ui(r.scenarioBTotalCost, 'USD'),
              },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        // Breakeven
        if (r.breakevenMonths < 9999)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: _refiColor.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
              border: Border.all(color: _refiColor.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.timeline, color: _refiColor, size: 16),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isEs
                      ? 'Punto de equilibrio: ${r.breakevenMonths} meses (~${(r.breakevenMonths / 12).toStringAsFixed(1)} años).'
                      : 'Breakeven: ${r.breakevenMonths} months (~${(r.breakevenMonths / 12).toStringAsFixed(1)} years).',
                  style: const TextStyle(
                      fontSize: AppTextSize.sm, color: _refiColor),
                ),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _sectionHeader(String text, {Color? color}) => Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: AppTextSize.bodyMd,
          color: color ?? _helocColor,
        ),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    bool intOnly = false,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: intOnly
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
              intOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(labelText: label, hintText: hint),
      );
}
