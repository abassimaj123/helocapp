import 'dart:math' show pow;

import 'package:fl_chart/fl_chart.dart';
import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/freemium/freemium_service.dart';
import '../core/heloc_engine.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/premium_cta_widget.dart';

// ---------------------------------------------------------------------------
// Model
// ---------------------------------------------------------------------------

class _PlannedDraw {
  String name;
  double amount;
  int month; // month number (1-based) within the draw period

  _PlannedDraw({required this.name, required this.amount, required this.month});

  _PlannedDraw copyWith({String? name, double? amount, int? month}) =>
      _PlannedDraw(
        name: name ?? this.name,
        amount: amount ?? this.amount,
        month: month ?? this.month,
      );
}

class _StrategyResult {
  final String label;
  final List<_PlannedDraw> draws;
  final double interestDuringDraw;
  final double balanceAtDrawEnd;
  final double totalInterest;
  final int payoffMonths;

  const _StrategyResult({
    required this.label,
    required this.draws,
    required this.interestDuringDraw,
    required this.balanceAtDrawEnd,
    required this.totalInterest,
    required this.payoffMonths,
  });
}

/// A single rate-change event for variable rate simulation.
class _RateStep {
  int startYear; // 1-based year within entire period (draw + repay)
  double ratePct;

  _RateStep({required this.startYear, required this.ratePct});

  _RateStep copyWith({int? startYear, double? ratePct}) => _RateStep(
      startYear: startYear ?? this.startYear, ratePct: ratePct ?? this.ratePct);
}

// ---------------------------------------------------------------------------
// Engine helpers (private)
// ---------------------------------------------------------------------------

/// Simulate draws: interest accrues on outstanding balance each month.
/// Returns (interestDuringDraw, balanceAtDrawEnd, totalInterest, payoffMonths).
(double, double, double, int) _simulateStrategy(
  List<_PlannedDraw> draws,
  double annualRate,
  int drawPeriodMonths,
  int repayYears,
) {
  final r = annualRate / 100 / 12;
  double balance = 0;
  double interestDuringDraw = 0;

  // Sort by month
  final sorted = [...draws]..sort((a, b) => a.month.compareTo(b.month));

  for (int m = 1; m <= drawPeriodMonths; m++) {
    // Apply draws that happen this month
    for (final d in sorted) {
      if (d.month == m) balance += d.amount;
    }
    // Interest-only payment
    interestDuringDraw += balance * r;
  }

  final balanceAtDrawEnd = balance;

  // Repayment phase — standard amortization
  double repayInterest = 0;
  int payoffMonths = 0;
  if (balance > 0.01 && r > 0) {
    final n = repayYears * 12;
    final payment = balance * r * pow(1 + r, n) / (pow(1 + r, n) - 1);
    double bal = balance;
    for (int m = 0; m < n && bal > 0.01; m++) {
      final interest = bal * r;
      repayInterest += interest;
      bal -= (payment - interest);
      if (bal < 0) bal = 0;
      payoffMonths = m + 1;
    }
  }

  return (
    interestDuringDraw,
    balanceAtDrawEnd,
    interestDuringDraw + repayInterest,
    drawPeriodMonths + payoffMonths,
  );
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class DrawOptimizerScreen extends StatefulWidget {
  const DrawOptimizerScreen({super.key});

  @override
  State<DrawOptimizerScreen> createState() => _DrawOptimizerScreenState();
}

class _DrawOptimizerScreenState extends State<DrawOptimizerScreen> {
  final _creditLimitCtrl = TextEditingController(text: '150000');
  final _rateCtrl = TextEditingController(text: '8.5');
  final _drawYearsCtrl = TextEditingController(text: '10');
  final _repayYearsCtrl = TextEditingController(text: '20');

  final _fmt =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _fmtDec =
      NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

  final List<_PlannedDraw> _draws = [
    _PlannedDraw(name: 'Kitchen Renovation', amount: 40000, month: 1),
    _PlannedDraw(name: 'Bathroom Remodel', amount: 25000, month: 6),
    _PlannedDraw(name: 'Roof Repair', amount: 15000, month: 18),
  ];

  List<_StrategyResult>? _results;
  int? _optimalIndex;

  // ── Variable rate simulation state ────────────────────────────────────────
  final _primeRateCtrl = TextEditingController(text: '8.0');
  final _marginCtrl = TextEditingController(text: '0.5');
  // Up to 3 rate change events
  final List<_RateStep> _rateSteps = [];
  List<Map<String, double>>? _varRateSchedule;
  bool _varRateExpanded = false;

  double _parseCtrl(TextEditingController c) {
    final s = c.text.replaceAll(',', '');
    return double.tryParse(s) ?? 0;
  }

  int _parseInt(TextEditingController c) => int.tryParse(c.text) ?? 0;

  void _addDraw() {
    if (_draws.length >= 5) return;
    setState(() {
      _draws.add(_PlannedDraw(name: '', amount: 0, month: 1));
    });
  }

  void _removeDraw(int index) {
    setState(() => _draws.removeAt(index));
    setState(() => _results = null);
  }

  void _optimize() {
    final rate = _parseCtrl(_rateCtrl);
    final drawYears = _parseInt(_drawYearsCtrl);
    final repayYears = _parseInt(_repayYearsCtrl);
    if (rate <= 0 || drawYears <= 0 || repayYears <= 0) return;

    final validDraws = _draws.where((d) => d.amount > 0).toList();
    if (validDraws.isEmpty) return;

    final drawPeriodMonths = drawYears * 12;

    // Strategy 1: user-defined order
    final (i1, b1, t1, p1) =
        _simulateStrategy(validDraws, rate, drawPeriodMonths, repayYears);

    // Strategy 2: all at once (month 1)
    final allAtOnce = validDraws
        .map((d) => _PlannedDraw(name: d.name, amount: d.amount, month: 1))
        .toList();
    final (i2, b2, t2, p2) =
        _simulateStrategy(allAtOnce, rate, drawPeriodMonths, repayYears);

    // Strategy 3: spread evenly — each draw at its original relative position
    //   but rescaled to evenly distribute across draw period
    final n = validDraws.length;
    final spreadDraws = List.generate(n, (idx) {
      final spreadMonth = (((idx + 1) / (n + 1)) * drawPeriodMonths)
          .round()
          .clamp(1, drawPeriodMonths);
      return _PlannedDraw(
        name: validDraws[idx].name,
        amount: validDraws[idx].amount,
        month: spreadMonth,
      );
    });
    final (i3, b3, t3, p3) =
        _simulateStrategy(spreadDraws, rate, drawPeriodMonths, repayYears);

    final results = [
      _StrategyResult(
        label: 'Your Plan',
        draws: validDraws,
        interestDuringDraw: i1,
        balanceAtDrawEnd: b1,
        totalInterest: t1,
        payoffMonths: p1,
      ),
      _StrategyResult(
        label: 'All at Once',
        draws: allAtOnce,
        interestDuringDraw: i2,
        balanceAtDrawEnd: b2,
        totalInterest: t2,
        payoffMonths: p2,
      ),
      _StrategyResult(
        label: 'Spread Evenly',
        draws: spreadDraws,
        interestDuringDraw: i3,
        balanceAtDrawEnd: b3,
        totalInterest: t3,
        payoffMonths: p3,
      ),
    ];

    // Find optimal = minimum total interest
    int optimal = 0;
    for (int i = 1; i < results.length; i++) {
      if (results[i].totalInterest < results[optimal].totalInterest) {
        optimal = i;
      }
    }

    setState(() {
      _results = results;
      _optimalIndex = optimal;
    });

    HapticFeedback.mediumImpact();
  }

  @override
  void dispose() {
    _creditLimitCtrl.dispose();
    _rateCtrl.dispose();
    _drawYearsCtrl.dispose();
    _repayYearsCtrl.dispose();
    _primeRateCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  // ── Variable rate helpers ─────────────────────────────────────────────────

  double _parsePrime() =>
      double.tryParse(_primeRateCtrl.text.replaceAll(',', '')) ?? 8.0;
  double _parseMargin() =>
      double.tryParse(_marginCtrl.text.replaceAll(',', '')) ?? 0.5;

  double get _effectiveBaseRate => _parsePrime() + _parseMargin();

  void _addRateStep() {
    if (_rateSteps.length >= 3) return;
    final drawYears = _parseInt(_drawYearsCtrl);
    setState(() {
      _rateSteps.add(_RateStep(
        startYear: (_rateSteps.isEmpty ? 2 : _rateSteps.last.startYear + 2)
            .clamp(1, drawYears + _parseInt(_repayYearsCtrl)),
        ratePct: _effectiveBaseRate + 1.0,
      ));
      _varRateSchedule = null;
    });
  }

  void _removeRateStep(int i) => setState(() {
        _rateSteps.removeAt(i);
        _varRateSchedule = null;
      });

  void _runVariableRateSimulation() {
    final drawYears = _parseInt(_drawYearsCtrl);
    final repayYears = _parseInt(_repayYearsCtrl);
    final totalDraw = _draws.fold(0.0, (s, d) => s + d.amount);
    if (totalDraw <= 0 || drawYears <= 0 || repayYears <= 0) return;

    // Build step list: first entry is the base rate at year 1
    final steps = <({int startYear, double ratePct})>[
      (startYear: 1, ratePct: _effectiveBaseRate),
      ..._rateSteps.map((s) => (startYear: s.startYear, ratePct: s.ratePct)),
    ];

    setState(() {
      _varRateSchedule = HelocEngine.variableRateSchedule(
        drawAmount: totalDraw,
        drawYears: drawYears,
        repayYears: repayYears,
        rateSteps: steps,
      );
      _varRateExpanded = true;
    });
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return Scaffold(
      appBar: AppBar(
        title:
            Text(isEs ? 'Optimizador de Disposición' : 'Draw Period Optimizer'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                          color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          color: AppTheme.primary, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isEs
                              ? 'Compara cómo el momento de tus disposiciones afecta los intereses totales.'
                              : 'See how the timing of your draws affects total interest paid.',
                          style: const TextStyle(
                              fontSize: AppTextSize.sm,
                              color: AppTheme.primary),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // Parameters
                  Text(
                    isEs ? 'Parámetros del HELOC' : 'HELOC Parameters',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTextSize.bodyLg),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    ctrl: _creditLimitCtrl,
                    label:
                        isEs ? 'Límite de crédito (\$)' : 'Credit Limit (\$)',
                    hint: '150000',
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    ctrl: _rateCtrl,
                    label: isEs ? 'Tasa HELOC (%)' : 'HELOC Rate (%)',
                    hint: '8.5',
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _buildField(
                        ctrl: _drawYearsCtrl,
                        label: isEs
                            ? 'Período disposición (años)'
                            : 'Draw Period (yrs)',
                        hint: '10',
                        intOnly: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildField(
                        ctrl: _repayYearsCtrl,
                        label:
                            isEs ? 'Período de pago (años)' : 'Repayment (yrs)',
                        hint: '20',
                        intOnly: true,
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  // Planned draws
                  Row(children: [
                    Expanded(
                      child: Text(
                        isEs
                            ? 'Disposiciones planificadas (máx. 5)'
                            : 'Planned Draws (max 5)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextSize.bodyLg),
                      ),
                    ),
                    if (_draws.length < 5)
                      TextButton.icon(
                        onPressed: _addDraw,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: Text(isEs ? 'Añadir' : 'Add'),
                        style: TextButton.styleFrom(
                            foregroundColor: AppTheme.primary),
                      ),
                  ]),
                  const SizedBox(height: 8),

                  ..._draws.asMap().entries.map((entry) {
                    final i = entry.key;
                    final d = entry.value;
                    return _DrawEntryCard(
                      index: i,
                      draw: d,
                      isEs: isEs,
                      drawPeriodMonths: (_parseInt(_drawYearsCtrl)) * 12,
                      onChanged: (updated) {
                        setState(() {
                          _draws[i] = updated;
                          _results = null;
                        });
                      },
                      onRemove: _draws.length > 1 ? () => _removeDraw(i) : null,
                    );
                  }),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: _optimize,
                    icon: const Icon(Icons.auto_graph),
                    label: Text(
                        isEs ? 'Analizar estrategias' : 'Analyze Strategies'),
                  ),

                  if (_results != null) ...[
                    const SizedBox(height: 28),
                    _buildResults(isEs),
                  ],

                  const SizedBox(height: 28),

                  // ── Variable Rate Simulation (Premium) ─────────────────
                  ValueListenableBuilder<bool>(
                    valueListenable: freemiumService.isPremiumNotifier,
                    builder: (_, isPremium, __) {
                      if (!isPremium) {
                        return PremiumCtaWidget(
                          feature: isEs
                              ? 'Simulación de Tasa Variable'
                              : 'Variable Rate Simulation',
                        );
                      }
                      return _buildVariableRateSection(isEs);
                    },
                  ),

                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
          const CalcwiseAdFooter(),
        ],
      ),
    );
  }

  // ── Variable rate simulation UI ───────────────────────────────────────────

  Widget _buildVariableRateSection(bool isEs) {
    final totalDraw = _draws.fold(0.0, (s, d) => s + d.amount);
    final drawYears = _parseInt(_drawYearsCtrl);
    final repayYears = _parseInt(_repayYearsCtrl);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(children: [
          const Icon(Icons.show_chart, color: AppTheme.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              isEs ? 'Simulación de Tasa Variable' : 'Variable Rate Simulation',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: AppTextSize.bodyLg),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: CalcwiseSemanticColors.warnBg,
              borderRadius: BorderRadius.circular(AppRadius.mdPlus),
              border: Border.all(color: CalcwiseSemanticColors.warnBorder),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded, color: CalcwiseSemanticColors.warnIcon, size: 12),
              const SizedBox(width: 3),
              const Text('Premium',
                  style: TextStyle(
                      fontSize: 10,
                      color: CalcwiseSemanticColors.warnIcon,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          isEs
              ? 'Simula cómo cambios en la tasa prime afectan tu costo total.'
              : 'Simulate how prime rate changes affect your total interest cost.',
          style: const TextStyle(
              fontSize: AppTextSize.sm, color: AppTheme.labelGray),
        ),
        const SizedBox(height: 16),

        // Base rate inputs: prime + margin
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.mdPlus),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEs ? 'Tasa base' : 'Base Rate',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: AppTextSize.body),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: _buildField(
                      ctrl: _primeRateCtrl,
                      label: isEs ? 'Tasa prime (%)' : 'Prime Rate (%)',
                      hint: '8.0',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('+',
                        style: TextStyle(
                            fontSize: AppTextSize.subtitle,
                            color: AppTheme.labelGray,
                            fontWeight: FontWeight.bold)),
                  ),
                  Expanded(
                    child: _buildField(
                      ctrl: _marginCtrl,
                      label: isEs ? 'Margen (%)' : 'Margin (%)',
                      hint: '0.5',
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Effective rate badge
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _primeRateCtrl,
                    builder: (_, __, ___) =>
                        ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _marginCtrl,
                      builder: (_, __, ___) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
                          border: Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.3)),
                        ),
                        child: Column(children: [
                          Text(
                            isEs ? 'Efectiva' : 'Effective',
                            style: const TextStyle(
                                fontSize: 9, color: AppTheme.labelGray),
                          ),
                          Text(
                            '${_effectiveBaseRate.toStringAsFixed(2)}%',
                            style: const TextStyle(
                                fontSize: AppTextSize.body,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.primary),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Rate change events
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.mdPlus),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      isEs
                          ? 'Cambios de tasa (máx. 3)'
                          : 'Rate Change Events (max 3)',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: AppTextSize.body),
                    ),
                  ),
                  if (_rateSteps.length < 3)
                    TextButton.icon(
                      onPressed: _addRateStep,
                      icon: const Icon(Icons.add_rounded, size: 16),
                      label: Text(isEs ? 'Añadir' : 'Add',
                          style: const TextStyle(fontSize: AppTextSize.sm)),
                      style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                ]),
                const SizedBox(height: 4),
                if (_rateSteps.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      isEs
                          ? 'Sin cambios de tasa — se usa la tasa base para todo el período.'
                          : 'No rate changes — base rate applies for the full period.',
                      style: const TextStyle(
                          fontSize: AppTextSize.sm,
                          color: AppTheme.labelGray,
                          fontStyle: FontStyle.italic),
                    ),
                  )
                else
                  ..._rateSteps.asMap().entries.map((e) {
                    final i = e.key;
                    final step = e.value;
                    return _RateStepCard(
                      index: i,
                      step: step,
                      isEs: isEs,
                      maxYear: drawYears + repayYears,
                      onChanged: (updated) => setState(() {
                        _rateSteps[i] = updated;
                        _varRateSchedule = null;
                      }),
                      onRemove: () => _removeRateStep(i),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        // Run simulation button
        ElevatedButton.icon(
          onPressed: (totalDraw > 0 && drawYears > 0 && repayYears > 0)
              ? _runVariableRateSimulation
              : null,
          icon: const Icon(Icons.area_chart),
          label: Text(
              isEs ? 'Simular tasa variable' : 'Run Variable Rate Simulation'),
        ),

        // Results
        if (_varRateSchedule != null && _varRateExpanded) ...[
          const SizedBox(height: 20),
          _VarRateResults(
            schedule: _varRateSchedule!,
            rateSteps: [
              (startYear: 1, ratePct: _effectiveBaseRate),
              ..._rateSteps
                  .map((s) => (startYear: s.startYear, ratePct: s.ratePct)),
            ],
            drawYears: drawYears,
            repayYears: repayYears,
            totalDraw: totalDraw,
            isEs: isEs,
            fmt: _fmt,
            fmtDec: _fmtDec,
          ),
        ],
      ],
    );
  }

  Widget _buildResults(bool isEs) {
    final results = _results!;
    final optimal = _optimalIndex!;
    final optimalResult = results[optimal];
    final allAtOnceTotal =
        results.firstWhere((r) => r.label == 'All at Once').totalInterest;
    final spreadTotal =
        results.firstWhere((r) => r.label == 'Spread Evenly').totalInterest;
    final savings = allAtOnceTotal - spreadTotal;

    String _optimalLocalLabel() {
      if (isEs) {
        switch (optimalResult.label) {
          case 'Your Plan':
            return 'Tu Plan';
          case 'All at Once':
            return 'Todo a la Vez';
          case 'Spread Evenly':
            return 'Distribuido';
        }
      }
      return optimalResult.label;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isEs ? 'Análisis de estrategias' : 'Strategy Analysis',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: AppTextSize.subtitle),
        ),
        const SizedBox(height: 12),

        // Hero KPI — optimal strategy total interest
        Semantics(
          label:
              '${isEs ? "Mejor estrategia" : "Best strategy"}: ${_optimalLocalLabel()}. ${isEs ? "Interés total" : "Total interest"}: ${_fmt.format(optimalResult.totalInterest)}',
          child: CalcwiseHeroCard(
            label: isEs ? 'Mejor Estrategia' : 'Best Strategy',
            value: _fmt.format(optimalResult.totalInterest),
            secondary: _optimalLocalLabel(),
            stats: [
              (
                label: isEs ? 'Interés en disposición' : 'Draw Phase Interest',
                value: _fmt.format(optimalResult.interestDuringDraw),
              ),
              (
                label: isEs ? 'Plazo total' : 'Payoff Timeline',
                value: isEs
                    ? '${(optimalResult.payoffMonths / 12).toStringAsFixed(1)} años'
                    : '${(optimalResult.payoffMonths / 12).toStringAsFixed(1)} yrs',
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        ...results.asMap().entries.map((entry) {
          final i = entry.key;
          final r = entry.value;
          final isOptimal = i == optimal;
          return _StrategyCard(
            result: r,
            isOptimal: isOptimal,
            isEs: isEs,
            fmt: _fmt,
            fmtDec: _fmtDec,
          );
        }),

        const SizedBox(height: 16),

        // Summary banner
        Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.savings_rounded,
                color: AppTheme.success, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                savings > 0
                    ? (isEs
                        ? 'Distribuir las disposiciones ahorra ${_fmt.format(savings)} vs retirar todo a la vez.'
                        : 'Spreading draws saves ${_fmt.format(savings)} vs drawing all at once.')
                    : (isEs
                        ? 'Retirar todo a la vez es igual de eficiente para tu plan.'
                        : 'Drawing all at once is equally efficient for your plan.'),
                style: const TextStyle(
                  fontSize: AppTextSize.md,
                  color: CalcwiseSemanticColors.successDeep,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ]),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    bool intOnly = false,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: intOnly
          ? TextInputType.number
          : const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
            intOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]')),
      ],
      onChanged: (_) => setState(() => _results = null),
      decoration: InputDecoration(labelText: label, hintText: hint),
    );
  }
}

// ---------------------------------------------------------------------------
// Draw entry card
// ---------------------------------------------------------------------------

class _DrawEntryCard extends StatefulWidget {
  final int index;
  final _PlannedDraw draw;
  final bool isEs;
  final int drawPeriodMonths;
  final void Function(_PlannedDraw) onChanged;
  final VoidCallback? onRemove;

  const _DrawEntryCard({
    required this.index,
    required this.draw,
    required this.isEs,
    required this.drawPeriodMonths,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_DrawEntryCard> createState() => _DrawEntryCardState();
}

class _DrawEntryCardState extends State<_DrawEntryCard> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _amountCtrl;
  late final TextEditingController _monthCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.draw.name);
    _amountCtrl = TextEditingController(
        text: widget.draw.amount > 0
            ? widget.draw.amount.toStringAsFixed(0)
            : '');
    _monthCtrl = TextEditingController(text: widget.draw.month.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _amountCtrl.dispose();
    _monthCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final amount = double.tryParse(_amountCtrl.text.replaceAll(',', '')) ?? 0;
    final month = (int.tryParse(_monthCtrl.text) ?? 1)
        .clamp(1, widget.drawPeriodMonths.clamp(1, 360));
    widget.onChanged(widget.draw.copyWith(
      name: _nameCtrl.text,
      amount: amount,
      month: month,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${isEs ? 'Disposición' : 'Draw'} ${widget.index + 1}',
                  style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: AppTextSize.sm,
                      fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (widget.onRemove != null)
                IconButton(
                  icon: const Icon(Icons.close_rounded,
                      size: 18, color: AppTheme.labelGray),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: widget.onRemove,
                ),
            ]),
            const SizedBox(height: 10),
            TextFormField(
              controller: _nameCtrl,
              onChanged: (_) => _notify(),
              decoration: InputDecoration(
                labelText: isEs ? 'Nombre / propósito' : 'Name / purpose',
                hintText:
                    isEs ? 'ej. Remodelación cocina' : 'e.g. Kitchen Reno',
              ),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                flex: 2,
                child: TextFormField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  onChanged: (_) => _notify(),
                  decoration: InputDecoration(
                    labelText: isEs ? 'Monto (\$)' : 'Amount (\$)',
                    hintText: '25000',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _monthCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  ],
                  onChanged: (_) => _notify(),
                  decoration: InputDecoration(
                    labelText: isEs ? 'Mes' : 'Month',
                    hintText: '1',
                  ),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Strategy card
// ---------------------------------------------------------------------------

class _StrategyCard extends StatelessWidget {
  final _StrategyResult result;
  final bool isOptimal;
  final bool isEs;
  final NumberFormat fmt;
  final NumberFormat fmtDec;

  const _StrategyCard({
    required this.result,
    required this.isOptimal,
    required this.isEs,
    required this.fmt,
    required this.fmtDec,
  });

  String _localLabel() {
    if (isEs) {
      switch (result.label) {
        case 'Your Plan':
          return 'Tu Plan';
        case 'All at Once':
          return 'Todo a la Vez';
        case 'Spread Evenly':
          return 'Distribuido';
      }
    }
    return result.label;
  }

  @override
  Widget build(BuildContext context) {
    final borderColor =
        isOptimal ? AppTheme.success : CalcwiseTheme.of(context).cardBorder;
    final years = (result.payoffMonths / 12).toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isOptimal
            ? AppTheme.success.withValues(alpha: 0.04)
            : null, // null uses card theme color (works in both light and dark)
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: borderColor, width: isOptimal ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.mdPlus),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(
                _localLabel(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.bodyMd,
                  color: isOptimal ? AppTheme.success : AppTheme.primary,
                ),
              ),
              if (isOptimal) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.success,
                    borderRadius: BorderRadius.circular(AppRadius.xxl),
                  ),
                  child: Text(
                    isEs ? 'ÓPTIMO' : 'OPTIMAL',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _Metric(
                label:
                    isEs ? 'Interés fase disposición' : 'Draw Phase Interest',
                value: fmt.format(result.interestDuringDraw),
                color: AppTheme.labelGray,
              ),
              const SizedBox(width: 12),
              _Metric(
                label: isEs ? 'Balance al final' : 'Balance at Draw End',
                value: fmt.format(result.balanceAtDrawEnd),
                color: AppTheme.primary,
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              _Metric(
                label: isEs ? 'Interés total' : 'Total Interest',
                value: fmt.format(result.totalInterest),
                color: CalcwiseSemanticColors.errorDark,
              ),
              const SizedBox(width: 12),
              _Metric(
                label: isEs ? 'Plazo total' : 'Payoff Timeline',
                value: isEs ? '$years años' : '$years yrs',
                color: AppTheme.labelGray,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 10, color: AppTheme.labelGray)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: AppTextSize.body,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}

// ============================================================================
// Rate Step Card — single row for one rate change event
// ============================================================================

class _RateStepCard extends StatefulWidget {
  final int index;
  final _RateStep step;
  final bool isEs;
  final int maxYear;
  final void Function(_RateStep) onChanged;
  final VoidCallback onRemove;

  const _RateStepCard({
    required this.index,
    required this.step,
    required this.isEs,
    required this.maxYear,
    required this.onChanged,
    required this.onRemove,
  });

  @override
  State<_RateStepCard> createState() => _RateStepCardState();
}

class _RateStepCardState extends State<_RateStepCard> {
  late final TextEditingController _yearCtrl;
  late final TextEditingController _rateCtrl;

  @override
  void initState() {
    super.initState();
    _yearCtrl = TextEditingController(text: widget.step.startYear.toString());
    _rateCtrl =
        TextEditingController(text: widget.step.ratePct.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _yearCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    final year = (int.tryParse(_yearCtrl.text) ?? 1).clamp(1, widget.maxYear);
    final rate = double.tryParse(_rateCtrl.text.replaceAll(',', '')) ??
        widget.step.ratePct;
    widget.onChanged(widget.step.copyWith(startYear: year, ratePct: rate));
  }

  @override
  Widget build(BuildContext context) {
    final isEs = widget.isEs;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: CalcwiseSemanticColors.warnBg,
        borderRadius: BorderRadius.circular(AppRadius.mdPlus),
        border: Border.all(color: CalcwiseSemanticColors.warnBorder),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: CalcwiseSemanticColors.warnBg,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            '${isEs ? 'Cambio' : 'Change'} ${widget.index + 1}',
            style: const TextStyle(
                fontSize: AppTextSize.xs,
                fontWeight: FontWeight.w700,
                color: CalcwiseSemanticColors.warnIcon),
          ),
        ),
        const SizedBox(width: 10),
        // Year field
        Expanded(
          child: TextFormField(
            controller: _yearCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9]'))
            ],
            onChanged: (_) => _notify(),
            decoration: InputDecoration(
              labelText: isEs ? 'Año' : 'Year',
              hintText: '2',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: const Text('→',
              style: TextStyle(
                  fontSize: AppTextSize.bodyLg,
                  color: CalcwiseSemanticColors.warnIcon,
                  fontWeight: FontWeight.bold)),
        ),
        // Rate field
        Expanded(
          child: TextFormField(
            controller: _rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
            ],
            onChanged: (_) => _notify(),
            decoration: InputDecoration(
              labelText: isEs ? 'Nueva tasa (%)' : 'New Rate (%)',
              hintText: '9.5',
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            ),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          icon: const Icon(Icons.close_rounded,
              size: 16, color: AppTheme.labelGray),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: widget.onRemove,
        ),
      ]),
    );
  }
}

// ============================================================================
// Variable Rate Results — summary card + interest chart
// ============================================================================

class _VarRateResults extends StatelessWidget {
  final List<Map<String, double>> schedule;
  final List<({int startYear, double ratePct})> rateSteps;
  final int drawYears;
  final int repayYears;
  final double totalDraw;
  final bool isEs;
  final NumberFormat fmt;
  final NumberFormat fmtDec;

  const _VarRateResults({
    required this.schedule,
    required this.rateSteps,
    required this.drawYears,
    required this.repayYears,
    required this.totalDraw,
    required this.isEs,
    required this.fmt,
    required this.fmtDec,
  });

  @override
  Widget build(BuildContext context) {
    if (schedule.isEmpty) return const SizedBox.shrink();

    final totalInterest = HelocEngine.totalInterestFromSchedule(schedule);
    // Fixed-rate baseline for comparison
    final baseRate = rateSteps.first.ratePct;
    final fixedTotalInterest = HelocEngine.totalInterestPaid(
        totalDraw, baseRate, drawYears, repayYears);
    final diff = totalInterest - fixedTotalInterest;

    // Build monthly interest series for chart (sample every 3 months)
    final interestSpots = <FlSpot>[];
    double cumInterest = 0;
    for (int i = 0; i < schedule.length; i++) {
      final row = schedule[i];
      final phase = (row['phase'] ?? 0).toInt();
      double interest;
      if (phase == 0) {
        interest = row['payment'] ?? 0;
      } else {
        final prevBal = i > 0 ? (schedule[i - 1]['balance'] ?? 0.0) : totalDraw;
        final bal = row['balance'] ?? 0.0;
        final principal = (prevBal - bal).clamp(0.0, double.infinity);
        interest =
            ((row['payment'] ?? 0) - principal).clamp(0.0, double.infinity);
      }
      cumInterest += interest;
      if (i % 3 == 0 || i == schedule.length - 1) {
        interestSpots.add(FlSpot(row['month']!, cumInterest));
      }
    }

    // Vertical lines at each rate change (besides year 1)
    final rateChangeLines = rateSteps.where((s) => s.startYear > 1).map((s) {
      final month = (s.startYear - 1) * 12 + 1.0;
      return VerticalLine(
        x: month,
        color: Colors.orange.withValues(alpha: 0.7),
        strokeWidth: 1.5,
        dashArray: [4, 3],
        label: VerticalLineLabel(
          show: true,
          labelResolver: (_) => '${s.ratePct.toStringAsFixed(1)}%',
          style: const TextStyle(fontSize: 9, color: Colors.orange),
        ),
      );
    }).toList();

    final drawEndMonth = (drawYears * 12).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary card
        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.xl),
            side: BorderSide(
              color: diff > 0
                  ? Colors.red.withValues(alpha: 0.3)
                  : Colors.green.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.summarize_rounded,
                      color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    isEs ? 'Resumen: Tasa Variable' : 'Variable Rate Summary',
                    style: const TextStyle(
                        fontSize: AppTextSize.bodyMd,
                        fontWeight: FontWeight.w600),
                  ),
                ]),
                const SizedBox(height: 12),
                // Rate step legend
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: rateSteps
                      .map((s) => Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: s.startYear == 1
                                  ? AppTheme.primary.withValues(alpha: 0.1)
                                  : Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              border: Border.all(
                                color: s.startYear == 1
                                    ? AppTheme.primary.withValues(alpha: 0.3)
                                    : Colors.orange.shade200,
                              ),
                            ),
                            child: Text(
                              '${isEs ? 'Año' : 'Yr'} ${s.startYear}: ${s.ratePct.toStringAsFixed(2)}%',
                              style: TextStyle(
                                fontSize: AppTextSize.xs,
                                fontWeight: FontWeight.w600,
                                color: s.startYear == 1
                                    ? AppTheme.primary
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: _VarMetric(
                      label: isEs
                          ? 'Interés total (variable)'
                          : 'Total Interest (Variable)',
                      value: fmt.format(totalInterest),
                      color: Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _VarMetric(
                      label: isEs
                          ? 'Interés total (tasa fija ${baseRate.toStringAsFixed(1)}%)'
                          : 'Total Interest (Fixed ${baseRate.toStringAsFixed(1)}%)',
                      value: fmt.format(fixedTotalInterest),
                      color: AppTheme.primary,
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.smPlus),
                  decoration: BoxDecoration(
                    color: diff > 0 ? CalcwiseSemanticColors.errorBg : CalcwiseSemanticColors.successBg,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: diff > 0
                          ? CalcwiseSemanticColors.errorBorder
                          : CalcwiseSemanticColors.successBorder,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      diff > 0 ? Icons.trending_up : Icons.trending_down,
                      color: diff > 0
                          ? CalcwiseSemanticColors.errorDark
                          : CalcwiseSemanticColors.successDark,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        diff > 0
                            ? (isEs
                                ? 'Las subidas de tasa añaden ${fmt.format(diff.abs())} en interés vs tasa fija.'
                                : 'Rate increases add ${fmt.format(diff.abs())} in interest vs fixed rate.')
                            : (isEs
                                ? 'Las bajadas de tasa ahorran ${fmt.format(diff.abs())} vs tasa fija.'
                                : 'Rate decreases save ${fmt.format(diff.abs())} vs fixed rate.'),
                        style: TextStyle(
                          fontSize: AppTextSize.sm,
                          color: diff > 0
                              ? CalcwiseSemanticColors.errorDark
                              : CalcwiseSemanticColors.successDeep,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Cumulative interest chart
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEs
                      ? 'Interés acumulado a lo largo del tiempo'
                      : 'Cumulative Interest Over Time',
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: AppTextSize.body),
                ),
                const SizedBox(height: 4),
                Text(
                  isEs
                      ? 'Las líneas naranjas indican cambios de tasa'
                      : 'Orange lines mark rate changes',
                  style: const TextStyle(
                      fontSize: AppTextSize.xs, color: AppTheme.labelGray),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final chartHeight =
                        (constraints.maxWidth < 400) ? 200.0 : 240.0;
                    return SizedBox(
                      height: chartHeight,
                      child: interestSpots.length < 2
                          ? Center(
                              child: Text(isEs ? 'Sin datos' : 'No data',
                                  style: const TextStyle(
                                      color: AppTheme.labelGray)))
                          : LineChart(
                              LineChartData(
                                lineTouchData: LineTouchData(
                                  enabled: true,
                                  handleBuiltInTouches: true,
                                  touchTooltipData: LineTouchTooltipData(
                                    getTooltipColor: (_) =>
                                        Colors.blueGrey.shade800,
                                    getTooltipItems: (spots) => spots
                                        .map((s) => LineTooltipItem(
                                              '\$${(s.y / 1000).toStringAsFixed(1)}k',
                                              const TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: AppTextSize.sm),
                                            ))
                                        .toList(),
                                  ),
                                ),
                                gridData: FlGridData(
                                  drawVerticalLine: false,
                                  getDrawingHorizontalLine: (_) => FlLine(
                                      color:
                                          CalcwiseTheme.of(context).cardBorder,
                                      strokeWidth: 1),
                                ),
                                titlesData: FlTitlesData(
                                  leftTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 56,
                                      getTitlesWidget: (v, _) => Text(
                                        '\$${(v / 1000).toStringAsFixed(0)}k',
                                        style: const TextStyle(
                                            fontSize: 9,
                                            color: AppTheme.labelGray),
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
                                            fontSize: 9,
                                            color: AppTheme.labelGray),
                                      ),
                                    ),
                                  ),
                                  topTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(
                                      sideTitles:
                                          SideTitles(showTitles: false)),
                                ),
                                borderData: FlBorderData(show: false),
                                extraLinesData: ExtraLinesData(verticalLines: [
                                  VerticalLine(
                                    x: drawEndMonth,
                                    color:
                                        AppTheme.primary.withValues(alpha: 0.5),
                                    strokeWidth: 1.5,
                                    dashArray: [5, 4],
                                    label: VerticalLineLabel(
                                      show: true,
                                      labelResolver: (_) =>
                                          isEs ? 'Fin disp.' : 'Draw End',
                                      style: const TextStyle(
                                          fontSize: 8, color: AppTheme.primary),
                                    ),
                                  ),
                                  ...rateChangeLines,
                                ]),
                                lineBarsData: [
                                  LineChartBarData(
                                    spots: interestSpots,
                                    isCurved: true,
                                    color: Colors.red.shade600,
                                    barWidth: 2.5,
                                    dotData: const FlDotData(show: false),
                                    belowBarData: BarAreaData(
                                      show: true,
                                      color: Colors.red.withValues(alpha: 0.07),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Monthly payment table for first 24 months
        _VarRateMonthlyTable(
          schedule: schedule.take(24).toList(),
          isEs: isEs,
          fmtDec: fmtDec,
        ),
      ],
    );
  }
}

class _VarMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _VarMetric(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(fontSize: 10, color: AppTheme.labelGray)),
      const SizedBox(height: 3),
      Text(value,
          style: TextStyle(
              fontSize: AppTextSize.bodyMd,
              fontWeight: FontWeight.w700,
              color: color)),
    ]);
  }
}

class _VarRateMonthlyTable extends StatelessWidget {
  final List<Map<String, double>> schedule;
  final bool isEs;
  final NumberFormat fmtDec;

  const _VarRateMonthlyTable({
    required this.schedule,
    required this.isEs,
    required this.fmtDec,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isEs
                  ? 'Primeros 24 meses (tasa variable)'
                  : 'First 24 Months (Variable Rate)',
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: AppTextSize.body),
            ),
            const SizedBox(height: 10),
            // Header
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(children: [
                _th(isEs ? 'Mes' : 'Mo', flex: 1),
                _th(isEs ? 'Tasa' : 'Rate', flex: 2),
                _th(isEs ? 'Pago' : 'Payment', flex: 3),
                _th(isEs ? 'Balance' : 'Balance', flex: 3),
              ]),
            ),
            const SizedBox(height: 4),
            ...schedule.map((row) {
              final month = row['month']!.toInt();
              final rate = row['rate']!;
              final payment = row['payment']!;
              final balance = row['balance']!;
              final isDrawPhase = (row['phase'] ?? 0).toInt() == 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 8),
                child: Row(children: [
                  Expanded(
                      flex: 1,
                      child: Text('$month',
                          style: const TextStyle(fontSize: AppTextSize.xs))),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: CalcwiseSemanticColors.warnBg,
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                      child: Text(
                        '${rate.toStringAsFixed(1)}%',
                        style: const TextStyle(
                            fontSize: 10,
                            color: CalcwiseSemanticColors.warnIcon,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  Expanded(
                      flex: 3,
                      child: Text(fmtDec.format(payment),
                          style: const TextStyle(fontSize: AppTextSize.xs))),
                  Expanded(
                    flex: 3,
                    child: Text(
                      fmtDec.format(balance),
                      style: TextStyle(
                        fontSize: AppTextSize.xs,
                        color:
                            isDrawPhase ? AppTheme.primary : AppTheme.success,
                        fontWeight: FontWeight.w500,
                      ),
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

  Widget _th(String text, {required int flex}) => Expanded(
        flex: flex,
        child: Text(text,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTextSize.xs,
                color: AppTheme.primary)),
      );
}
