import 'dart:async';
import 'dart:math' show pow;

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/services/pdf_export_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import '../widgets/save_scenario_button.dart';
import 'history_screen.dart';

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
  final _helocRateCtrl = TextEditingController(text: '7.5');
  final _refiRateCtrl = TextEditingController(text: '6.5');
  final _closingPctCtrl = TextEditingController(text: '3');

  bool _financeClosing = true;
  int _helocDrawYears = 10;
  int _helocRepayYears = 20;

  _CompareCashoutResult? _result;

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('heloc_vs_cashout');
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
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryCompute());
  }

  void _onLangChange() => setState(() {});

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    smartHistoryService.cancelPendingSave('helocapp', 'heloc_vs_cashout');
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

  double _roundTo(double v, double step) => (v / step).round() * step;

  Map<String, String> _buildL1(_CompareCashoutResult r) {
    final isEs = isSpanishNotifier.value;
    return {
      isEs ? 'Ganador' : 'Winner': r.winnerIndex == 0 ? 'HELOC' : (isEs ? 'Refi con Retiro' : 'Cash-Out Refi'),
      isEs ? 'Interés Total HELOC 30a' : 'HELOC Total Interest 30y': AmountFormatter.ui(r.scenarioATotalInterest30y, 'USD'),
      isEs ? 'Costo Total Refi' : 'Refi Total Cost': AmountFormatter.ui(r.scenarioBTotalCost, 'USD'),
      isEs ? 'HELOC Mensual (inicial)' : 'HELOC Monthly (initial)': AmountFormatter.ui(r.scenarioATotalMonthly, 'USD'),
      isEs ? 'Refi Mensual' : 'Refi Monthly': AmountFormatter.ui(r.refiMonthly, 'USD'),
    };
  }

  Map<String, dynamic> _buildL2(_CompareCashoutResult r) => {
        'inputs': {
          'home_value': _parseN(_homeValueCtrl.text),
          'existing_balance': _parseN(_existingBalCtrl.text),
          'existing_rate': _parseN(_existingRateCtrl.text),
          'existing_years': _existingYearsCtrl.text,
          'cash_needed': _parseN(_cashCtrl.text),
          'heloc_rate': _parseN(_helocRateCtrl.text),
          'refi_rate': _parseN(_refiRateCtrl.text),
          'closing_pct': _parseN(_closingPctCtrl.text),
          'finance_closing': _financeClosing,
        },
        'results': {
          'heloc_io': r.helocIO,
          'heloc_pi': r.helocPI,
          'scenario_a_total_monthly': r.scenarioATotalMonthly,
          'scenario_a_total_interest_30y': r.scenarioATotalInterest30y,
          'refi_new_balance': r.refiNewBalance,
          'refi_monthly': r.refiMonthly,
          'refi_closing_costs': r.refiClosingCosts,
          'scenario_b_total_interest_30y': r.scenarioBTotalInterest30y,
          'scenario_b_total_cost': r.scenarioBTotalCost,
          'breakeven_months': r.breakevenMonths,
          'winner_index': r.winnerIndex,
        },
      };

  void _scheduleAutoSave(_CompareCashoutResult r) {
    final hash = ResultHasher.hashMixed({
      'existing_bal': _roundTo(_parseN(_existingBalCtrl.text), 1000),
      'cash': _roundTo(_parseN(_cashCtrl.text), 500),
      'heloc_rate': _roundTo(_parseN(_helocRateCtrl.text), 0.25),
      'refi_rate': _roundTo(_parseN(_refiRateCtrl.text), 0.25),
    });
    smartHistoryService.scheduleAutoSave(
      appKey: 'helocapp',
      screenId: 'heloc_vs_cashout',
      inputHash: hash,
      l1: _buildL1(r),
      l2: _buildL2(r),
    );
    HistoryScreen.refreshNotifier.value++;
  }

  Future<void> _saveScenario(String? label) async {
    if (_result == null) return;
    final hash = ResultHasher.hashMixed({
      'existing_bal': _roundTo(_parseN(_existingBalCtrl.text), 1000),
      'cash': _roundTo(_parseN(_cashCtrl.text), 500),
      'heloc_rate': _roundTo(_parseN(_helocRateCtrl.text), 0.25),
      'refi_rate': _roundTo(_parseN(_refiRateCtrl.text), 0.25),
    });
    await smartHistoryService.saveScenario(
      appKey: 'helocapp',
      screenId: 'heloc_vs_cashout',
      inputHash: hash,
      l1: _buildL1(_result!),
      l2: _buildL2(_result!),
      label: label ?? (isSpanishNotifier.value
          ? 'HELOC vs Refinanc. \$${(_parseN(_cashCtrl.text) / 1000).toStringAsFixed(0)}k'
          : 'HELOC vs Refi \$${(_parseN(_cashCtrl.text) / 1000).toStringAsFixed(0)}k'),
    );
  }

  Future<void> _exportPdf() async {
    final r = _result;
    if (r == null) return;
    final isEs = isSpanishNotifier.value;
    Future<void> doExport() => PdfExportService.exportHelocVsCashout(
          context: context,
          homeValue: _parseN(_homeValueCtrl.text),
          existingBalance: _parseN(_existingBalCtrl.text),
          existingRate: _parseN(_existingRateCtrl.text),
          existingYears: int.tryParse(_existingYearsCtrl.text) ?? 0,
          cashNeeded: _parseN(_cashCtrl.text),
          helocRate: _parseN(_helocRateCtrl.text),
          refiRate: _parseN(_refiRateCtrl.text),
          closingPct: _parseN(_closingPctCtrl.text),
          financeClosing: _financeClosing,
          helocIOPayment: r.helocIO,
          helocPIPayment: r.existingMortgagePI + r.helocPI,
          helocTotalMonthly: r.scenarioATotalMonthly,
          helocTotalInterest30y: r.scenarioATotalInterest30y,
          refiNewBalance: r.refiNewBalance,
          refiMonthly: r.refiMonthly,
          refiClosingCosts: r.refiClosingCosts,
          refiTotalInterest30y: r.scenarioBTotalInterest30y,
          refiTotalCost: r.scenarioBTotalCost,
          breakevenMonths: r.breakevenMonths,
          winnerIndex: r.winnerIndex,
          isEs: isEs,
          isFr: false,
        );
    if (freemiumService.hasFullAccess) {
      await doExport();
    } else {
      await PdfExportService.showUnlockOrPay(context, doExport);
    }
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
    final helocPI = _amortizedPayment(cash, helocRate, _helocRepayYears);
    final aMonthly = existingPI + helocIO;
    // Total interest 30y: existing mortgage interest + heloc IO (draw years) + heloc P&I (repay years)
    final existingTotalInt =
        _totalInterestAmort(existingBal, existingRate, existingYears);
    final helocIOTotal = helocIO * 12 * _helocDrawYears;
    final helocPITotal = (helocPI * 12 * _helocRepayYears) - cash;
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
      final aPay = existingPI + (m <= _helocDrawYears * 12 ? helocIO : helocPI);
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
    final newResult = _CompareCashoutResult(
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
    );
    setState(() => _result = newResult);
    _scheduleAutoSave(newResult);

    if (silent) return;
    adService.onAction();
    AnalyticsService.instance.log('heloc_vs_cashout_calculated');
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
    _homeValueCtrl.text = '500000';
    _existingBalCtrl.text = '250000';
    _existingRateCtrl.text = '4.0';
    _existingYearsCtrl.text = '25';
    _cashCtrl.text = '75000';
    _helocRateCtrl.text = '7.5';
    _refiRateCtrl.text = '6.5';
    _closingPctCtrl.text = '3';
    setState(() {
      _financeClosing = true;
      _helocDrawYears = 10;
      _helocRepayYears = 20;
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
              child: CalcwisePageEntrance(
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
                    _sectionHeader(isEs ? 'Períodos HELOC' : 'HELOC Periods'),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          initialValue: _helocDrawYears.toString(),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
                          decoration: InputDecoration(
                            labelText: isEs ? 'Años disposición' : 'Draw years',
                            hintText: '10',
                          ),
                          onChanged: (v) {
                            final val = int.tryParse(v);
                            if (val != null && val > 0) {
                              setState(() => _helocDrawYears = val);
                              scheduleCalc(_tryCompute);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: TextFormField(
                          initialValue: _helocRepayYears.toString(),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))],
                          decoration: InputDecoration(
                            labelText: isEs ? 'Años pago' : 'Repay years',
                            hintText: '20',
                          ),
                          onChanged: (v) {
                            final val = int.tryParse(v);
                            if (val != null && val > 0) {
                              setState(() => _helocRepayYears = val);
                              scheduleCalc(_tryCompute);
                            }
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: AppSpacing.xl),
                    _sectionHeader(isEs ? 'Tasas' : 'Rates', color: _refiColor),
                    const SizedBox(height: AppSpacing.md),
                    Row(children: [
                      Expanded(
                          child: _field(
                              ctrl: _helocRateCtrl,
                              label: isEs ? 'Tasa HELOC (%)' : 'HELOC rate (%)',
                              hint: '7.5')),
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
                      onChanged: (v) {
                        setState(() => _financeClosing = v);
                        scheduleCalc(_tryCompute);
                      },
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
                    if (_result != null &&
                        (freemiumService.hasFullAccess ||
                            freemiumService.isRewarded)) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SaveScenarioButton(onSave: _saveScenario),
                    ],
                    if (_result != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      OutlinedButton.icon(
                        onPressed: _exportPdf,
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
                          ? const SizedBox.shrink(key: ValueKey('empty'))
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
