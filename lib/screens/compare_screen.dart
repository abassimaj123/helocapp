import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/ads/ad_service.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/paywall_service.dart';
import '../core/heloc_engine.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';
import '../widgets/banner_ad_widget.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';

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

class _CompareScreenState extends State<CompareScreen> {
  final _formKey = GlobalKey<FormState>();

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

  final _fmt = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _fmtDec = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);

  HelocCompareResult? _result;

  @override
  void dispose() {
    for (final c in [_drawCtrl, _helocRateCtrl, _drawYearsCtrl, _repayYearsCtrl,
                     _refiRateCtrl, _refiTermCtrl, _closingCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  void _compare() {
    if (!_formKey.currentState!.validate()) return;
    final result = HelocEngine.compare(
      withdrawalAmount: _parseN(_drawCtrl.text),
      helocRate: _parseN(_helocRateCtrl.text),
      helocDrawYears: int.tryParse(_drawYearsCtrl.text) ?? 10,
      helocRepayYears: int.tryParse(_repayYearsCtrl.text) ?? 20,
      refiRate: _parseN(_refiRateCtrl.text),
      refiTermYears: int.tryParse(_refiTermCtrl.text) ?? 30,
      refiClosingCosts: _parseN(_closingCtrl.text),
    );
    setState(() => _result = result);
    AdService.instance.onCalculation();
    AnalyticsService.instance.logCompareViewed(
      withdrawalAmount: _parseN(_drawCtrl.text),
      helocRate: _parseN(_helocRateCtrl.text),
      refiRate: _parseN(_refiRateCtrl.text),
    );
    final trigger = paywallService.recordAction();
    if (trigger == PaywallTrigger.hard && !freemiumService.isPremium) {
      PaywallHard.show(context);
    } else if (trigger == PaywallTrigger.soft && !freemiumService.isPremium) {
      PaywallSoft.show(context);
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
    setState(() => _result = null);
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
                  // ── Header info banner ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.info_outline, color: AppTheme.primary, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isEs
                              ? 'Compara el costo real de acceder al mismo capital con ambas opciones.'
                              : 'Compare the true cost of accessing the same equity under each option.',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primary),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 20),

                  // ── Shared input ───────────────────────────────────────
                  _sectionHeader(isEs ? 'Capital a acceder' : 'Equity to Access'),
                  const SizedBox(height: 12),
                  _field(
                    ctrl: _drawCtrl,
                    label: isEs ? 'Monto (\$)' : 'Amount (\$)',
                    hint: '100000',
                    validator: (v) => _parseN(v ?? '') <= 0
                        ? (isEs ? 'Ingresa un monto' : 'Enter amount')
                        : null,
                  ),

                  const SizedBox(height: 20),

                  // ── HELOC column ───────────────────────────────────────
                  _sectionHeader(
                    isEs ? 'Opción A — HELOC' : 'Option A — HELOC',
                    color: AppTheme.primary,
                  ),
                  const SizedBox(height: 12),
                  _field(
                    ctrl: _helocRateCtrl,
                    label: isEs ? 'Tasa HELOC (%)' : 'HELOC Rate (%)',
                    hint: '8.5',
                    validator: (v) => _parseN(v ?? '') <= 0
                        ? (isEs ? 'Ingresa una tasa' : 'Enter rate')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                      child: _field(
                        ctrl: _drawYearsCtrl,
                        label: isEs ? 'Período disposición (años)' : 'Draw Period (yrs)',
                        hint: '10',
                        intOnly: true,
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        ctrl: _repayYearsCtrl,
                        label: isEs ? 'Período de pago (años)' : 'Repayment (yrs)',
                        hint: '20',
                        intOnly: true,
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                  ]),

                  const SizedBox(height: 20),

                  // ── Cash-out Refi column ───────────────────────────────
                  _sectionHeader(
                    isEs ? 'Opción B — Refinanciación con Retiro de Capital' : 'Option B — Cash-Out Refinance',
                    color: const Color(0xFF01579B),
                  ),
                  const SizedBox(height: 12),
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
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        ctrl: _refiTermCtrl,
                        label: isEs ? 'Plazo (años)' : 'Term (yrs)',
                        hint: '30',
                        intOnly: true,
                        validator: (v) => (int.tryParse(v ?? '') ?? 0) <= 0 ? '?' : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  _field(
                    ctrl: _closingCtrl,
                    label: isEs ? 'Costos de cierre (\$)' : 'Closing Costs (\$)',
                    hint: '5000',
                    validator: (v) => _parseN(v ?? '') < 0 ? '?' : null,
                  ),

                  const SizedBox(height: 24),

                  ElevatedButton.icon(
                    onPressed: _compare,
                    icon: const Icon(Icons.compare_arrows),
                    label: Text(isEs ? 'Comparar opciones' : 'Compare Options'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _reset,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(isEs ? 'Limpiar' : 'Reset'),
                  ),

                  // ── Results ────────────────────────────────────────────
                  if (_result != null) ...[
                    const SizedBox(height: 28),
                    _buildResults(isEs, _result!),
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

  Widget _buildResults(bool isEs, HelocCompareResult r) {
    final helocWinsShort = r.helocCheaperShortTerm;
    final helocWinsLong = r.helocCheaperLongTerm;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Verdict banner
        _verdictBanner(isEs, helocWinsShort),
        const SizedBox(height: 16),

        // Side-by-side header
        _columnHeader(isEs),
        const SizedBox(height: 8),

        // Monthly costs
        _compRow(
          isEs ? 'Pago mensual (fase inicial)' : 'Monthly (initial phase)',
          _fmtDec.format(r.helocDrawPayment),
          _fmtDec.format(r.refiMonthlyPayment),
          note1: isEs ? 'Solo interés' : 'Interest-only',
          note2: isEs ? 'Capital + interés' : 'Principal + interest',
          winner: r.helocDrawPayment < r.refiMonthlyPayment ? 0 : 1,
        ),
        _compRow(
          isEs ? 'Pago mensual (fase de pago)' : 'Monthly (repayment phase)',
          _fmtDec.format(r.helocRepayPayment),
          _fmtDec.format(r.refiMonthlyPayment),
          winner: r.helocRepayPayment < r.refiMonthlyPayment ? 0 : 1,
        ),
        _compRow(
          isEs ? 'Costos iniciales' : 'Upfront costs',
          r.helocClosingCosts > 0 ? _fmt.format(r.helocClosingCosts) : ('\$0'),
          r.refiClosingCosts > 0 ? _fmt.format(r.refiClosingCosts) : '\$0',
          winner: 0,
        ),
        const Divider(height: 24),
        _compRow(
          isEs ? 'Interés total + costos (10 años)' : 'Total cost over 10 years',
          _fmt.format(r.helocInterestOver10Yrs),
          _fmt.format(r.refiInterestOver10Yrs),
          highlight: true,
          winner: helocWinsShort ? 0 : 1,
        ),
        _compRow(
          isEs ? 'Interés total (vida del producto)' : 'Total interest (full term)',
          _fmt.format(r.helocTotalInterest),
          _fmt.format(r.refiTotalInterest),
          winner: helocWinsLong ? 0 : 1,
        ),

        // Break-even info
        if (r.refiBreakEvenMonths < 9999) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF01579B).withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF01579B).withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const Icon(Icons.timeline, color: Color(0xFF01579B), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  isEs
                      ? 'La refinanciación recupera los costos de cierre en ${r.refiBreakEvenMonths} meses '
                        '(comparado con el pago de reembolso del HELOC).'
                      : 'Cash-out refi recovers closing costs in ${r.refiBreakEvenMonths} months '
                        '(vs. HELOC repayment payment).',
                  style: const TextStyle(fontSize: 12, color: Color(0xFF01579B)),
                ),
              ),
            ]),
          ),
        ],

        // Guidance
        const SizedBox(height: 16),
        _guidanceCard(isEs, r),
      ],
    );
  }

  Widget _verdictBanner(bool isEs, bool helocWins) {
    final color = helocWins ? AppTheme.primary : const Color(0xFF01579B);
    final icon = helocWins ? Icons.water_outlined : Icons.home_work_outlined;
    final title = helocWins
        ? (isEs ? '✅ HELOC es más económico en 10 años' : '✅ HELOC is cheaper over 10 years')
        : (isEs ? '✅ La refinanciación es más económica en 10 años' : '✅ Cash-out Refi is cheaper over 10 years');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Row(children: [
        Icon(icon, color: Colors.white, size: 24),
        const SizedBox(width: 12),
        Expanded(
          child: Text(title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ]),
    );
  }

  Widget _columnHeader(bool isEs) {
    return Row(children: [
      const SizedBox(width: 140),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(8), bottomLeft: Radius.circular(8)),
          ),
          child: Center(
            child: Text('HELOC',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary, fontSize: 13)),
          ),
        ),
      ),
      const SizedBox(width: 4),
      Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF01579B).withValues(alpha: 0.1),
            borderRadius: const BorderRadius.only(topRight: Radius.circular(8), bottomRight: Radius.circular(8)),
          ),
          child: Center(
            child: Text(isEs ? 'Refi' : 'Cash-out Refi',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF01579B), fontSize: 13)),
          ),
        ),
      ),
    ]);
  }

  Widget _compRow(String label, String val1, String val2, {
    String? note1, String? note2, bool highlight = false, int winner = -1,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 140,
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.labelGray,
                  fontWeight: highlight ? FontWeight.w600 : FontWeight.normal)),
        ),
        Expanded(
          child: _valueCell(val1, note1,
              isWinner: winner == 0,
              highlight: highlight,
              winColor: AppTheme.primary),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: _valueCell(val2, note2,
              isWinner: winner == 1,
              highlight: highlight,
              winColor: const Color(0xFF01579B)),
        ),
      ]),
    );
  }

  Widget _valueCell(String value, String? note, {
    required bool isWinner, required bool highlight, required Color winColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isWinner ? winColor.withValues(alpha: 0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: isWinner ? Border.all(color: winColor.withValues(alpha: 0.3)) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Text(value,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: highlight ? FontWeight.bold : FontWeight.w600,
                fontSize: highlight ? 15 : 13,
                color: isWinner ? winColor : null)),
        if (note != null)
          Text(note,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: AppTheme.labelGray)),
      ]),
    );
  }

  Widget _guidanceCard(bool isEs, HelocCompareResult r) {
    final bullets = <String>[];
    if (r.helocCheaperShortTerm) {
      bullets.add(isEs
          ? '📉 Si planeas quedarte menos de ${_breakEvenYears(r)} años, el HELOC cuesta menos.'
          : '📉 If you plan to stay under ${_breakEvenYears(r)} years, HELOC costs less.');
    } else {
      bullets.add(isEs
          ? '💡 La refinanciación es más económica si te quedas en la vivienda a largo plazo.'
          : '💡 Cash-out refi is cheaper if you stay long-term.');
    }
    if (r.refiBreakEvenMonths < 36) {
      bullets.add(isEs
          ? '⚡ Los costos de cierre se recuperan rápido (${r.refiBreakEvenMonths} meses).'
          : '⚡ Closing costs recovered quickly (${r.refiBreakEvenMonths} months).');
    }
    bullets.add(isEs
        ? '🔒 El HELOC es flexible — solo pides lo que necesitas. La refinanciación bloquea el capital desde el inicio.'
        : '🔒 HELOC is flexible — draw only what you need. Refi locks in the full amount from day 1.');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEs ? '💡 Cómo elegir' : '💡 How to choose',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            ...bullets.map((b) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(b, style: const TextStyle(fontSize: 13, height: 1.4)),
            )),
          ],
        ),
      ),
    );
  }

  int _breakEvenYears(HelocCompareResult r) {
    if (r.refiBreakEvenMonths >= 9999) return 30;
    return (r.refiBreakEvenMonths / 12).ceil();
  }

  Widget _sectionHeader(String text, {Color? color}) => Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 15,
          color: color ?? AppTheme.primary,
        ),
      );

  Widget _field({
    required TextEditingController ctrl,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    bool intOnly = false,
  }) =>
      TextFormField(
        controller: ctrl,
        keyboardType: intOnly
            ? TextInputType.number
            : const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(intOnly ? RegExp(r'[0-9]') : RegExp(r'[0-9.,]')),
        ],
        decoration: InputDecoration(labelText: label, hintText: hint),
        validator: validator,
      );
}

extension on HelocCompareResult {
  double get helocClosingCosts => 0;
}
