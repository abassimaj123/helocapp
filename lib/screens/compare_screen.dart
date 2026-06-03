import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/heloc_engine.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';

// ── Option colors ─────────────────────────────────────────────────────────────
const _helocColor = AppTheme.primary;
const _refiColor = Color(0xFF01579B);
const _loanColor = Color(0xFF6A1B9A);

class CompareScreen extends StatefulWidget {
  const CompareScreen({super.key});

  @override
  State<CompareScreen> createState() => _CompareScreenState();
}

double _parseN(String v) {
  if (v.isEmpty) return 0.0;
  final s = (v.contains('.') && v.contains(','))
      ? v.replaceAll(',', '')
      : v.replaceAll(',', '.');
  return double.tryParse(s) ?? 0.0;
}

class _CompareResult {
  final HelocCompareResult heloc;
  final double loanMonthlyPayment;
  final double loanTotalInterest;

  const _CompareResult({
    required this.heloc,
    required this.loanMonthlyPayment,
    required this.loanTotalInterest,
  });
}

class _CompareScreenState extends State<CompareScreen>
    with CalcwiseAutoCalcMixin {
  final _formKey = GlobalKey<FormState>();

  // Skip form validation on the very first auto-calc so default values don't
  // surface validation errors before the user interacts.
  bool _firstRun = true;

  // Shared
  final _drawCtrl = TextEditingController(text: '100000');

  // HELOC
  final _helocRateCtrl = TextEditingController(text: '8.5');
  final _drawYearsCtrl = TextEditingController(text: '10');
  final _repayYearsCtrl = TextEditingController(text: '20');

  // Cash-out Refi
  final _refiRateCtrl = TextEditingController(text: '6.5');
  final _refiTermCtrl = TextEditingController(text: '30');
  final _closingCtrl = TextEditingController(text: '5000');

  // Personal Loan
  final _loanRateCtrl = TextEditingController(text: '12.0');
  final _loanTermCtrl = TextEditingController(text: '5');

  _CompareResult? _result;

  @override
  void initState() {
    super.initState();
    // Pre-fill draw amount and rate from the last calculator result.
    final h = helocNotifier.value;
    if (h.creditLimit > 0) {
      _drawCtrl.text = h.creditLimit.toStringAsFixed(0);
    }
    if (h.rate > 0) {
      _helocRateCtrl.text = h.rate.toStringAsFixed(1);
    }
    for (final c in [
      _drawCtrl,
      _helocRateCtrl,
      _drawYearsCtrl,
      _repayYearsCtrl,
      _refiRateCtrl,
      _refiTermCtrl,
      _closingCtrl,
      _loanRateCtrl,
      _loanTermCtrl,
    ]) {
      c.addListener(() => scheduleCalc(_compare));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _compare();
    });
  }

  @override
  void dispose() {
    for (final c in [
      _drawCtrl,
      _helocRateCtrl,
      _drawYearsCtrl,
      _repayYearsCtrl,
      _refiRateCtrl,
      _refiTermCtrl,
      _closingCtrl,
      _loanRateCtrl,
      _loanTermCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _compare({bool isManual = false}) async {
    // On the first auto-run, skip validation so default inputs don't display
    // errors before the user has interacted with the form.
    if (_firstRun) {
      _firstRun = false;
    } else if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    final amount = _parseN(_drawCtrl.text);
    final helocResult = HelocEngine.compare(
      withdrawalAmount: amount,
      helocRate: _parseN(_helocRateCtrl.text),
      helocDrawYears: int.tryParse(_drawYearsCtrl.text) ?? 10,
      helocRepayYears: int.tryParse(_repayYearsCtrl.text) ?? 20,
      refiRate: _parseN(_refiRateCtrl.text),
      refiTermYears: int.tryParse(_refiTermCtrl.text) ?? 30,
      refiClosingCosts: _parseN(_closingCtrl.text),
    );
    final loanRate = _parseN(_loanRateCtrl.text);
    final loanTerm = int.tryParse(_loanTermCtrl.text) ?? 5;
    final loanPayment =
        HelocEngine.personalLoanPayment(amount, loanRate, loanTerm);
    final loanInterest =
        HelocEngine.personalLoanTotalInterest(amount, loanRate, loanTerm);

    setState(() => _result = _CompareResult(
          heloc: helocResult,
          loanMonthlyPayment: loanPayment,
          loanTotalInterest: loanInterest,
        ));
    AnalyticsService.instance.logCompareViewed(
      withdrawalAmount: amount,
      helocRate: _parseN(_helocRateCtrl.text),
      refiRate: _parseN(_refiRateCtrl.text),
    );
    if (isManual) {
      adService.onAction();
      final trigger = await paywallSession.recordAction();
      if (trigger == PaywallTrigger.hard && !freemiumService.hasFullAccess) {
        PaywallHard.show(context);
      } else if (trigger == PaywallTrigger.soft &&
          !freemiumService.hasFullAccess) {
        PaywallSoft.show(context);
      }
    }
  }

  void _reset() {
    _drawCtrl.text = '100000';
    _helocRateCtrl.text = '8.5';
    _drawYearsCtrl.text = '10';
    _repayYearsCtrl.text = '20';
    _refiRateCtrl.text = '6.5';
    _refiTermCtrl.text = '30';
    _closingCtrl.text = '5000';
    _loanRateCtrl.text = '12.0';
    _loanTermCtrl.text = '5';
    setState(() => _result = null);
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return Column(
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
                  // ── Header info banner ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.mdPlus),
                    decoration: BoxDecoration(
                      color: _helocColor.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border:
                          Border.all(color: _helocColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline,
                          color: _helocColor, size: 18),
                      const SizedBox(width: AppSpacing.smPlus),
                      Expanded(
                        child: Text(
                          isEs
                              ? 'Compara el costo real de financiar tus renovaciones con las 3 opciones principales.'
                              : 'Compare the true cost of financing your renovation under all 3 options.',
                          style: const TextStyle(
                              fontSize: AppTextSize.sm, color: _helocColor),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // ── Shared input ───────────────────────────────────────
                  _sectionHeader(
                      isEs ? 'Capital a financiar' : 'Amount to Finance'),
                  const SizedBox(height: AppSpacing.md),
                  _field(
                    ctrl: _drawCtrl,
                    label: isEs ? 'Monto (\$)' : 'Amount (\$)',
                    hint: '100000',
                    validator: (v) => _parseN(v ?? '') <= 0
                        ? (isEs ? 'Ingresa un monto' : 'Enter amount')
                        : null,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── HELOC ──────────────────────────────────────────────
                  _sectionHeader(
                    isEs ? 'Opción A — HELOC' : 'Option A — HELOC',
                    color: _helocColor,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _field(
                    ctrl: _helocRateCtrl,
                    label: isEs ? 'Tasa HELOC (%)' : 'HELOC Rate (%)',
                    hint: '8.5',
                    validator: (v) => _parseN(v ?? '') <= 0
                        ? (isEs ? 'Ingresa una tasa' : 'Enter rate')
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(children: [
                    Expanded(
                      child: _field(
                        ctrl: _drawYearsCtrl,
                        label: isEs
                            ? 'Período disposición (años)'
                            : 'Draw Period (yrs)',
                        hint: '10',
                        intOnly: true,
                        validator: (v) =>
                            (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _field(
                        ctrl: _repayYearsCtrl,
                        label:
                            isEs ? 'Período de pago (años)' : 'Repayment (yrs)',
                        hint: '20',
                        intOnly: true,
                        validator: (v) =>
                            (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                  ]),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Cash-out Refi ──────────────────────────────────────
                  _sectionHeader(
                    isEs
                        ? 'Opción B — Refinanciación con Retiro de Capital'
                        : 'Option B — Cash-Out Refinance',
                    color: _refiColor,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(children: [
                    Expanded(
                      child: _field(
                        ctrl: _refiRateCtrl,
                        label: isEs ? 'Tasa refi (%)' : 'Refi Rate (%)',
                        hint: '6.5',
                        validator: (v) => _parseN(v ?? '') <= 0
                            ? (isEs ? 'Ingresa una tasa' : 'Enter rate')
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _field(
                        ctrl: _refiTermCtrl,
                        label: isEs ? 'Plazo (años)' : 'Term (yrs)',
                        hint: '30',
                        intOnly: true,
                        validator: (v) =>
                            (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.md),
                  _field(
                    ctrl: _closingCtrl,
                    label:
                        isEs ? 'Costos de cierre (\$)' : 'Closing Costs (\$)',
                    hint: '5000',
                    validator: (v) => _parseN(v ?? '') < 0 ? '?' : null,
                  ),

                  const SizedBox(height: AppSpacing.xl),

                  // ── Personal Loan ──────────────────────────────────────
                  _sectionHeader(
                    isEs
                        ? 'Opción C — Préstamo Personal'
                        : 'Option C — Personal Loan',
                    color: _loanColor,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(children: [
                    Expanded(
                      child: _field(
                        ctrl: _loanRateCtrl,
                        label: isEs ? 'Tasa préstamo (%)' : 'Loan Rate (%)',
                        hint: '12.0',
                        validator: (v) => _parseN(v ?? '') <= 0
                            ? (isEs ? 'Ingresa una tasa' : 'Enter rate')
                            : null,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: _field(
                        ctrl: _loanTermCtrl,
                        label: isEs ? 'Plazo (años)' : 'Term (yrs)',
                        hint: '5',
                        intOnly: true,
                        validator: (v) =>
                            (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                  ]),

                  const SizedBox(height: AppSpacing.xxl),

                  ElevatedButton.icon(
                    onPressed: () => _compare(isManual: true),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.xl)),
                    ),
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(isEs
                        ? 'Comparar las 3 opciones'
                        : 'Compare All 3 Options'),
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

                  // ── Results ────────────────────────────────────────────
                  if (_result != null) ...[
                    const SizedBox(height: AppSpacing.xxlPlus),
                    _buildResults(isEs, _result!),
                  ],
                  const SizedBox(height: AppSpacing.listBottomInset),
                ],
              ),
            ), // Form
            ), // CalcwisePageEntrance
          ),
        ),
        const CalcwiseAdFooter(),
      ],
    );
  }

  Widget _buildResults(bool isEs, _CompareResult cr) {
    final r = cr.heloc;

    // Find best option by total interest (full term)
    final helocTotal = r.helocTotalInterest;
    final refiTotal = r.refiTotalInterest;
    final loanTotal = cr.loanTotalInterest;
    final minTotal =
        [helocTotal, refiTotal, loanTotal].reduce((a, b) => a < b ? a : b);
    final bestIsHeloc = helocTotal == minTotal;
    final bestIsRefi = refiTotal == minTotal && !bestIsHeloc;
    final bestIsLoan = loanTotal == minTotal && !bestIsHeloc && !bestIsRefi;

    String bestName;
    if (bestIsHeloc)
      bestName = 'HELOC';
    else if (bestIsRefi)
      bestName = isEs ? 'Refinanciación' : 'Cash-Out Refi';
    else
      bestName = isEs ? 'Préstamo Personal' : 'Personal Loan';

    // Savings vs personal loan (most expensive usually)
    final maxTotal =
        [helocTotal, refiTotal, loanTotal].reduce((a, b) => a > b ? a : b);
    final savingsVsMax = maxTotal - minTotal;
    final worstName = helocTotal == maxTotal
        ? 'HELOC'
        : (refiTotal == maxTotal
            ? (isEs ? 'Refinanciación' : 'Cash-Out Refi')
            : (isEs ? 'Préstamo Personal' : 'Personal Loan'));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Best option banner
        _buildBestBanner(isEs, bestName, savingsVsMax, worstName),
        const SizedBox(height: AppSpacing.lg),

        // 3-column header
        _buildColumnHeader(isEs),
        const SizedBox(height: AppSpacing.sm),

        // Monthly payment (initial)
        _build3Row(
          isEs ? 'Pago mensual inicial' : 'Monthly (initial)',
          AmountFormatter.ui(r.helocDrawPayment, 'USD'),
          AmountFormatter.ui(r.refiMonthlyPayment, 'USD'),
          AmountFormatter.ui(cr.loanMonthlyPayment, 'USD'),
          note1: isEs ? 'Solo interés' : 'Interest-only',
          note2: isEs ? 'P + I' : 'P + I',
          note3: isEs ? 'P + I' : 'P + I',
          winner: _winnerOf(
              r.helocDrawPayment, r.refiMonthlyPayment, cr.loanMonthlyPayment),
        ),
        // Monthly payment (repayment phase)
        _build3Row(
          isEs ? 'Pago mensual (fase pago)' : 'Monthly (repayment)',
          AmountFormatter.ui(r.helocRepayPayment, 'USD'),
          AmountFormatter.ui(r.refiMonthlyPayment, 'USD'),
          AmountFormatter.ui(cr.loanMonthlyPayment, 'USD'),
          winner: _winnerOf(
              r.helocRepayPayment, r.refiMonthlyPayment, cr.loanMonthlyPayment),
        ),
        // Upfront costs
        _build3Row(
          isEs ? 'Costos iniciales' : 'Upfront costs',
          '\$0',
          r.refiClosingCosts > 0 ? AmountFormatter.ui(r.refiClosingCosts, 'USD') : '\$0',
          '\$0',
          winner: 0,
        ),
        const Divider(height: 24),
        // Total interest 10 years
        _build3Row(
          isEs ? 'Interés total (10 años)' : 'Total cost (10 years)',
          AmountFormatter.ui(r.helocInterestOver10Yrs, 'USD'),
          AmountFormatter.ui(r.refiInterestOver10Yrs, 'USD'),
          AmountFormatter.ui(_loanInterestOver10(cr), 'USD'),
          highlight: true,
          winner: _winnerOf(r.helocInterestOver10Yrs, r.refiInterestOver10Yrs,
              _loanInterestOver10(cr)),
        ),
        // Total interest full term
        _build3Row(
          isEs ? 'Interés total (vida útil)' : 'Total interest (full term)',
          AmountFormatter.ui(helocTotal, 'USD'),
          AmountFormatter.ui(refiTotal, 'USD'),
          AmountFormatter.ui(loanTotal, 'USD'),
          winner: _winnerOf(helocTotal, refiTotal, loanTotal),
        ),

        // Refi break-even note
        if (r.refiBreakEvenMonths < 9999) ...[
          const SizedBox(height: AppSpacing.md),
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
                      ? 'La refinanciación recupera costos de cierre en ${r.refiBreakEvenMonths} meses.'
                      : 'Cash-out refi recovers closing costs in ${r.refiBreakEvenMonths} months.',
                  style: const TextStyle(
                      fontSize: AppTextSize.sm, color: _refiColor),
                ),
              ),
            ]),
          ),
        ],

        // Guidance
        const SizedBox(height: AppSpacing.lg),
        _buildGuidance(isEs, cr),
      ],
    );
  }

  /// Approximate personal loan interest paid over first 10 years
  /// (or full term if < 10 years).
  double _loanInterestOver10(_CompareResult cr) {
    final term = int.tryParse(_loanTermCtrl.text) ?? 5;
    final months = [term * 12, 120].reduce((a, b) => a < b ? a : b);
    return cr.loanMonthlyPayment * months -
        (_parseN(_drawCtrl.text) * (months / (term * 12)));
  }

  // Returns 0 for HELOC, 1 for Refi, 2 for Personal Loan, -1 for no winner
  int _winnerOf(double a, double b, double c) {
    final min = [a, b, c].reduce((x, y) => x < y ? x : y);
    if (a == min) return 0;
    if (b == min) return 1;
    return 2;
  }

  Widget _buildBestBanner(
      bool isEs, String bestName, double savings, String worstName) {
    final color = bestName == 'HELOC'
        ? _helocColor
        : (bestName.contains('Refi') || bestName.contains('Refinan')
            ? _refiColor
            : _loanColor);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
              color: color.withValues(alpha: 0.25),
              blurRadius: 8,
              offset: const Offset(0, 3))
        ],
      ),
      child: Row(children: [
        const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 26),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              isEs ? '✅ Mejor opción: $bestName' : '✅ Best option: $bestName',
              style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: AppTextSize.bodyMd),
            ),
            if (savings > 0)
              Text(
                isEs
                    ? '$bestName ahorra ${AmountFormatter.ui(savings, 'USD')} vs $worstName'
                    : '$bestName saves ${AmountFormatter.ui(savings, 'USD')} vs $worstName',
                style: const TextStyle(
                    color: Colors.white70, fontSize: AppTextSize.sm),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildColumnHeader(bool isEs) {
    return Row(children: [
      const SizedBox(width: 110),
      _headerCell('HELOC', _helocColor, leftRound: true),
      const SizedBox(width: 3),
      _headerCell(isEs ? 'Refi' : 'Cash-Out Refi', _refiColor),
      const SizedBox(width: 3),
      _headerCell(isEs ? 'Préstamo' : 'Personal Loan', _loanColor,
          rightRound: true),
    ]);
  }

  Widget _headerCell(String label, Color color,
      {bool leftRound = false, bool rightRound = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.only(
            topLeft: leftRound ? const Radius.circular(8) : Radius.zero,
            bottomLeft: leftRound ? const Radius.circular(8) : Radius.zero,
            topRight: rightRound ? const Radius.circular(8) : Radius.zero,
            bottomRight: rightRound ? const Radius.circular(8) : Radius.zero,
          ),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                  fontSize: AppTextSize.xs),
              textAlign: TextAlign.center),
        ),
      ),
    );
  }

  Widget _build3Row(
    String label,
    String val0,
    String val1,
    String val2, {
    String? note1,
    String? note2,
    String? note3,
    bool highlight = false,
    int winner = -1,
  }) {
    final colors = [_helocColor, _refiColor, _loanColor];
    final vals = [val0, val1, val2];
    final notes = [note1, note2, note3];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(
                  fontSize: AppTextSize.xs,
                  color: AppTheme.labelGray,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.normal)),
        ),
        for (int i = 0; i < 3; i++) ...[
          if (i > 0) const SizedBox(width: 3),
          Expanded(
            child: _valueCell3(
              vals[i],
              notes[i],
              isWinner: winner == i,
              highlight: highlight,
              winColor: colors[i],
            ),
          ),
        ],
      ]),
    );
  }

  Widget _valueCell3(
    String value,
    String? note, {
    required bool isWinner,
    required bool highlight,
    required Color winColor,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 5),
      decoration: BoxDecoration(
        color: isWinner ? winColor.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: isWinner
            ? Border.all(color: winColor.withValues(alpha: 0.35))
            : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                fontSize: highlight ? 13 : 12,
                color: isWinner ? winColor : null)),
        if (note != null)
          Text(note,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: AppTextSize.xxs, color: AppTheme.labelGray)),
      ]),
    );
  }

  Widget _buildGuidance(bool isEs, _CompareResult cr) {
    final r = cr.heloc;
    final bullets = <String>[];
    bullets.add(isEs
        ? '🏠 HELOC: tasa variable, solo pagas lo que usas, flexible. Ideal si el proyecto puede extenderse.'
        : '🏠 HELOC: variable rate, draw only what you use, flexible. Best if project scope may grow.');
    bullets.add(isEs
        ? '🔄 Refinanciación: tasa fija más baja pero costos de cierre altos. Mejor para proyectos grandes a largo plazo.'
        : '🔄 Cash-Out Refi: lower fixed rate but high closing costs. Better for large, long-term projects.');
    bullets.add(isEs
        ? '💳 Préstamo Personal: aprobación rápida, sin garantía hipotecaria, pero tasa más alta. Mejor para montos pequeños.'
        : '💳 Personal Loan: fast approval, no home equity needed, but higher rate. Best for smaller amounts.');
    if (r.refiBreakEvenMonths < 9999 && r.refiBreakEvenMonths < 36) {
      bullets.add(isEs
          ? '⚡ La refinanciación recupera sus costos de cierre rápidamente (${r.refiBreakEvenMonths} meses).'
          : '⚡ Refi recovers closing costs quickly (${r.refiBreakEvenMonths} months).');
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEs ? '💡 ¿Cuál elegir?' : '💡 How to choose',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: AppTextSize.body)),
            const SizedBox(height: AppSpacing.smPlus),
            ...bullets.map((b) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(b,
                      style: const TextStyle(
                          fontSize: AppTextSize.sm, height: 1.4)),
                )),
          ],
        ),
      ),
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
    String? Function(String?)? validator,
    bool intOnly = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 0),
        child: TextFormField(
          controller: ctrl,
          keyboardType: intOnly
              ? TextInputType.number
              : const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(
                intOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]')),
          ],
          decoration: InputDecoration(labelText: label, hintText: hint),
          validator: validator,
        ),
      );
}
