import '../core/ads/ad_footer.dart';
import 'package:calcwise_core/calcwise_core.dart' show PaywallTrigger;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/db/database_service.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import 'history_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  final _fmtCur = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 0);
  final _fmtDec = NumberFormat.currency(locale: 'en_US', symbol: '\$', decimalDigits: 2);
  final _fmtDate = DateFormat('MMM d, yyyy – h:mm a');
  final _fmtPct = NumberFormat('##0.0#');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseService.instance.getHistory();
    if (mounted) {
      setState(() { _history = rows; _loading = false; });
      AnalyticsService.instance.logHistoryViewed();
      final trigger = await paywallSession.recordAction();
      if (trigger != PaywallTrigger.none && mounted && !freemiumService.isPremium) {
        if (trigger == PaywallTrigger.soft) {
          PaywallSoft.show(context);
        } else {
          PaywallHard.show(context);
        }
      }
    }
  }

  Future<void> _delete(int id) async {
    await DatabaseService.instance.deleteHistory(id);
    await _load();
  }

  Future<void> _clearAll() async {
    final isEs = isSpanishNotifier.value;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEs ? '¿Borrar todo?' : 'Clear all?'),
        content: Text(isEs
            ? '¿Eliminar todo el historial?'
            : 'Delete all history entries?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEs ? 'Borrar' : 'Clear',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseService.instance.clearHistory();
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                          child: ValueListenableBuilder<bool>(
                            valueListenable: freemiumService.isPremiumNotifier,
                            builder: (_, isPremium, __) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Expanded(
                                    child: Text(
                                      isPremium
                                          ? '${_history.length} ${isEs ? 'cálculos guardados' : 'entries saved'}'
                                          : '${_history.length} / ${MonetizationConfig.freeCalculationLimit} ${isEs ? 'guardados' : 'saved'}',
                                      style: const TextStyle(
                                          color: AppTheme.labelGray,
                                          fontSize: 13),
                                    ),
                                  ),
                                  if (isPremium && _history.isNotEmpty)
                                    TextButton.icon(
                                      onPressed: _clearAll,
                                      icon: const Icon(Icons.delete_sweep,
                                          size: 16, color: Colors.red),
                                      label: Text(
                                        isEs ? 'Borrar todo' : 'Clear all',
                                        style: const TextStyle(
                                            color: Colors.red, fontSize: 13),
                                      ),
                                    ),
                                ]),
                                if (!isPremium) ...[
                                  const SizedBox(height: 4),
                                  Row(children: [
                                    const Icon(Icons.lock_outline,
                                        size: 13, color: Colors.amber),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        isEs
                                            ? AppStringsES.historyLimit
                                            : AppStringsEN.historyLimit,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            color: AppTheme.labelGray),
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: () =>
                                          IAPService.instance.buy(),
                                      style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap),
                                      child: Text(
                                        isEs ? 'Desbloquear' : 'Unlock',
                                        style: const TextStyle(
                                            color: AppTheme.primary,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12),
                                      ),
                                    ),
                                  ]),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),

                      if (_history.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history,
                                    size: 64, color: const Color(0xFFCBD5E1)),
                                const SizedBox(height: 16),
                                Text(
                                  isEs
                                      ? AppStringsES.historyEmpty
                                      : AppStringsEN.historyEmpty,
                                  style: TextStyle(
                                      color: Color(0xFF64748B),
                                      fontSize: 16),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) {
                                final item = _history[i];
                                final id = item['id'] as int;
                                final inputs =
                                    item['inputs'] as Map<String, dynamic>;
                                final results =
                                    item['results'] as Map<String, dynamic>;
                                final createdAt = DateTime.parse(
                                    item['created_at'] as String);

                                final homeValue =
                                    (inputs['homeValue'] as num).toDouble();
                                final balance =
                                    (inputs['balance'] as num).toDouble();
                                final draw =
                                    (inputs['draw'] as num).toDouble();
                                final rate =
                                    (inputs['rate'] as num).toDouble();
                                final drawYears =
                                    (inputs['drawYears'] as num).toInt();
                                final repayYears =
                                    (inputs['repayYears'] as num).toInt();
                                final equity =
                                    (results['equity'] as num).toDouble();
                                final ltv =
                                    (results['ltv'] as num).toDouble();
                                final interestOnly =
                                    (results['interestOnly'] as num)
                                        .toDouble();
                                final repayment =
                                    (results['repayment'] as num).toDouble();

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Dismissible(
                                    key: ValueKey(id),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 20),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade400,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: const Icon(Icons.delete_outline,
                                          color: Colors.white, size: 26),
                                    ),
                                    confirmDismiss: (_) async {
                                      return await showDialog<bool>(
                                        context: context,
                                        builder: (ctx) => AlertDialog(
                                          title: Text(isEs
                                              ? '¿Eliminar entrada?'
                                              : 'Delete entry?'),
                                          content: Text(isEs
                                              ? '¿Eliminar este cálculo?'
                                              : 'Remove this calculation?'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, false),
                                              child: Text(isEs
                                                  ? 'Cancelar'
                                                  : 'Cancel'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(ctx, true),
                                              child: Text(
                                                isEs ? 'Eliminar' : 'Delete',
                                                style: const TextStyle(
                                                    color: Colors.red),
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                    onDismissed: (_) => _delete(id),
                                    child: Card(
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: () => HistoryDetailScreen.push(
                                          context,
                                          entry: item,
                                          onDelete: () => _delete(id),
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Expanded(
                                                  child: Text(
                                                    '${isEs ? 'Vivienda' : 'Home'}: ${_fmtCur.format(homeValue)}',
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15,
                                                        color:
                                                            AppTheme.primary),
                                                  ),
                                                ),
                                                const Icon(
                                                    Icons.chevron_right,
                                                    size: 18,
                                                    color: AppTheme.labelGray),
                                              ]),
                                              const SizedBox(height: 8),
                                              _HistoryRow(
                                                label: isEs
                                                    ? 'Hipoteca actual'
                                                    : 'Mortgage Balance',
                                                value: _fmtCur.format(balance),
                                              ),
                                              _HistoryRow(
                                                label: isEs
                                                    ? 'Monto dispuesto'
                                                    : 'Draw Amount',
                                                value: _fmtCur.format(draw),
                                              ),
                                              _HistoryRow(
                                                label:
                                                    isEs ? 'Tasa' : 'Rate',
                                                value:
                                                    '${rate.toStringAsFixed(2)}%',
                                              ),
                                              _HistoryRow(
                                                label: isEs
                                                    ? 'Período (disp/pago)'
                                                    : 'Period (draw/repay)',
                                                value:
                                                    '${drawYears}y / ${repayYears}y',
                                              ),
                                              const Divider(height: 14),
                                              _HistoryRow(
                                                label: isEs
                                                    ? 'Capital disponible'
                                                    : 'Available Equity',
                                                value: _fmtCur.format(equity),
                                                color: AppTheme.success,
                                              ),
                                              _HistoryRow(
                                                label: 'LTV',
                                                value:
                                                    '${_fmtPct.format(ltv)}%',
                                              ),
                                              _HistoryRow(
                                                label: isEs
                                                    ? 'Pago solo interés'
                                                    : 'Interest-Only Payment',
                                                value:
                                                    _fmtDec.format(interestOnly),
                                                bold: true,
                                                color: AppTheme.primary,
                                              ),
                                              _HistoryRow(
                                                label: isEs
                                                    ? 'Pago amortizado'
                                                    : 'Repayment Payment',
                                                value:
                                                    _fmtDec.format(repayment),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                _fmtDate.format(
                                                    createdAt.toLocal()),
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: AppTheme.labelGray),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _history.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
        const AdFooter(),
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;

  const _HistoryRow({
    required this.label,
    required this.value,
    this.bold = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.labelGray)),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        bold ? FontWeight.bold : FontWeight.w500,
                    color: color)),
          ],
        ),
      );
}
