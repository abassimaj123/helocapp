import 'dart:convert';

import 'package:calcwise_core/calcwise_core.dart' hide PaywallHard;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../core/db/database_service.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';
import '../widgets/paywall_hard.dart';
import '../widgets/paywall_soft.dart';
import 'history_detail_screen.dart';

enum _CardAction { unpin, rename, delete }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  static final refreshNotifier = ValueNotifier<int>(0);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  String _searchQuery = '';

  DateFormat get _fmtDate =>
      DateFormat('MMM d, yyyy – h:mm a', isSpanishNotifier.value ? 'es' : 'en');

  String _dateGroup(DateTime d, bool isEs) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final entry = DateTime(d.year, d.month, d.day);
    final diff = today.difference(entry).inDays;
    if (diff <= 0) return isEs ? 'Hoy' : 'Today';
    if (diff < 7) return isEs ? 'Esta semana' : 'This week';
    if (diff < 30) return isEs ? 'Este mes' : 'This month';
    return isEs ? 'Anterior' : 'Older';
  }

  /// The `inputs`/`results` shape (and this card's title/metric logic) is
  /// specific to calculator_screen. Compare/vs-cashout/payment-shock/
  /// draw-optimizer entries use different input keys ('draw_amount',
  /// 'home_value', 'credit_limit', ...), so reading 'draw'/'rate' off them
  /// silently returns 0 — showing every non-calculator entry as a
  /// nonsensical "$0 draw @ 0.0%" card. Detect the shape and fall back to
  /// the screen's own l1_json (already correctly labeled) instead.
  bool _isCalcShape(Map<String, dynamic> inputs) =>
      inputs.containsKey('homeValue') && inputs.containsKey('draw');

  Map<String, dynamic> _decodeL1(Map<String, dynamic> row) {
    final raw = row['l1_json'] as String?;
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  String _fmtL1Value(dynamic v) {
    if (v is String) return v;
    if (v is num) return AmountFormatter.ui(v.toDouble(), 'USD');
    return '$v';
  }

  String _shortK(double v) {
    if (v >= 1000000)
      return '\$${(v / 1000000).toStringAsFixed(v % 1000000 == 0 ? 0 : 1)}M';
    if (v >= 1000) return '\$${(v / 1000).toStringAsFixed(0)}k';
    return '\$${v.toStringAsFixed(0)}';
  }

  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('history');
    _load();
    HistoryScreen.refreshNotifier.addListener(_silentRefresh);
    isSpanishNotifier.addListener(_onLangChange);
  }

  void _onLangChange() => setState(() {});

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    HistoryScreen.refreshNotifier.removeListener(_silentRefresh);
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await DatabaseService.instance.getHistory();
    if (mounted) {
      setState(() {
        _history = rows;
        _loading = false;
      });
      AnalyticsService.instance.logHistoryViewed();
    }
  }

  Future<void> _silentRefresh() async {
    final rows = await DatabaseService.instance.getHistory();
    if (mounted) setState(() => _history = rows);
  }

  Future<void> _delete(int id) async {
    await smartHistoryService.delete(id);
    if (!mounted) return;
    await _load();
  }

  Future<void> _unpin(int id) async {
    await smartHistoryService.unpin(id);
    if (!mounted) return;
    await _load();
  }

  Future<void> _rename(Map<String, dynamic> row) async {
    final isEs = isSpanishNotifier.value;
    if (!freemiumService.hasFullAccess) {
      await PaywallHard.show(context, isSpanish: isSpanishNotifier.value);
      return;
    }
    final ctrl =
        TextEditingController(text: (row['pin_label'] as String?) ?? '');
    final label = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEs ? 'Renombrar escenario' : 'Rename scenario'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
              hintText: isEs ? 'Nombre del escenario' : 'Scenario name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, ctrl.text),
            child: Text(isEs ? 'Guardar' : 'Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (label == null) return;
    await smartHistoryService.rename(row['id'] as int, label.trim());
    if (!mounted) return;
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
                style: TextStyle(
                    color: CalcwiseSemanticColors.error(
                        Theme.of(context).brightness))),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      smartHistoryService.cancelPendingSave('helocapp', 'calculator');
      smartHistoryService.cancelPendingSave('helocapp', 'compare');
      smartHistoryService.cancelPendingSave('helocapp', 'draw_schedule');
      smartHistoryService.cancelPendingSave('helocapp', 'draw_optimizer');
      smartHistoryService.cancelPendingSave('helocapp', 'heloc_vs_cashout');
      smartHistoryService.cancelPendingSave('helocapp', 'payment_shock');
      await DatabaseService.instance.clearHistory();
      if (!mounted) return;
      await _load();
    }
  }

  List<Map<String, dynamic>> get _pinned =>
      _history.where((r) => (r['is_pinned'] as int? ?? 0) == 1).toList();

  List<Map<String, dynamic>> get _autoSaves =>
      _history.where((r) => (r['is_pinned'] as int? ?? 0) == 0).toList();

  List<Map<String, dynamic>> get _visibleAutoSaves {
    if (freemiumService.hasFullAccess || freemiumService.isRewarded) {
      return _autoSaves;
    }
    return _autoSaves.take(MonetizationConfig.freeRingBufferSize).toList();
  }

  bool _matchesSearch(Map<String, dynamic> row) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    final pinLabel = (row['pin_label'] as String? ?? '').toLowerCase();
    final inputs = row['inputs'] as Map<String, dynamic>? ?? {};
    if (pinLabel.contains(q)) return true;
    if (_isCalcShape(inputs)) {
      final draw = (inputs['draw'] as num?)?.toDouble() ?? 0.0;
      final rate = (inputs['rate'] as num?)?.toDouble() ?? 0.0;
      final humanLabel =
          '${_shortK(draw)} draw @ ${rate.toStringAsFixed(1)}%'.toLowerCase();
      return humanLabel.contains(q);
    }
    final l1 = _decodeL1(row);
    return l1.entries.any((e) =>
        e.key.toLowerCase().contains(q) ||
        _fmtL1Value(e.value).toLowerCase().contains(q));
  }

  List<Map<String, dynamic>> get _filteredPinned =>
      _pinned.where(_matchesSearch).toList();

  List<Map<String, dynamic>> get _filteredAutoSaves =>
      _visibleAutoSaves.where(_matchesSearch).toList();

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;

    return CalcwisePageEntrance(
        child: Column(
      children: [
        Expanded(
          child: _loading
              ? const _HistorySkeleton()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeader(context, isEs)),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg, AppSpacing.sm,
                              AppSpacing.lg, AppSpacing.xs),
                          child: CalcwiseSearchBar(
                            onChanged: (q) =>
                                setState(() => _searchQuery = q),
                          ),
                        ),
                      ),
                      if (_history.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: CalcwiseEmptyState(
                            icon: Icons.history_rounded,
                            title: isEs
                                ? AppStringsES.historyEmpty
                                : AppStringsEN.historyEmpty,
                            body: isEs
                                ? 'Tus cálculos guardados aparecerán aquí.'
                                : 'Your saved calculations will appear here.',
                            actionLabel: isEs
                                ? 'Hacer mi primer cálculo'
                                : 'Run my first calculation',
                            onAction: () => tabSwitchNotifier.value = 0,
                          ),
                        )
                      else if (_searchQuery.isNotEmpty &&
                          _filteredPinned.isEmpty &&
                          _filteredAutoSaves.isEmpty)
                        SliverToBoxAdapter(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Text(isEs ? 'Sin resultados' : 'No results'),
                            ),
                          ),
                        )
                      else ...[
                        // ── Saved Scenarios (pinned) ─────────────────────────
                        if (_filteredPinned.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _sectionHeader(
                                context,
                                isEs ? 'ESCENARIOS GUARDADOS' : 'SAVED SCENARIOS',
                                Icons.bookmark_rounded),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) => Padding(
                                padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                                    0, AppSpacing.lg, AppSpacing.smPlus),
                                child: _buildCard(_filteredPinned[i], isEs,
                                    pinned: true),
                              ),
                              childCount: _filteredPinned.length,
                            ),
                          ),
                        ],
                        // ── Recent Calculations (auto-saves) ─────────────────
                        if (_filteredAutoSaves.isNotEmpty) ...[
                          SliverToBoxAdapter(
                            child: _sectionHeader(
                                context,
                                isEs
                                    ? 'CÁLCULOS RECIENTES'
                                    : 'RECENT CALCULATIONS',
                                Icons.history_rounded),
                          ),
                          SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (ctx, i) {
                                final list = _filteredAutoSaves;
                                final row = list[i];
                                final id = row['id'] as int;
                                final createdAt =
                                    DateTime.parse(row['created_at'] as String);
                                final currentGroup =
                                    _dateGroup(createdAt.toLocal(), isEs);
                                final prevGroup = i == 0
                                    ? null
                                    : _dateGroup(
                                        DateTime.parse(
                                                list[i - 1]['created_at']
                                                    as String)
                                            .toLocal(),
                                        isEs);
                                final showHeader = currentGroup != prevGroup;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (showHeader)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            AppSpacing.xl,
                                            AppSpacing.sm,
                                            AppSpacing.xl,
                                            AppSpacing.sm),
                                        child: Text(
                                          currentGroup.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: AppTextSize.xs,
                                            fontWeight: FontWeight.w600,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                          AppSpacing.lg,
                                          0,
                                          AppSpacing.lg,
                                          AppSpacing.smPlus),
                                      child: Dismissible(
                                        key: ValueKey('hist_$id'),
                                        direction: DismissDirection.endToStart,
                                        background: Container(
                                          alignment: Alignment.centerRight,
                                          padding: const EdgeInsets.only(
                                              right: AppSpacing.xl),
                                          decoration: BoxDecoration(
                                            color: CalcwiseSemanticColors
                                                .errorBorder,
                                            borderRadius: BorderRadius.circular(
                                                AppRadius.xl),
                                          ),
                                          child: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.white,
                                              size: 26),
                                        ),
                                        confirmDismiss: (_) =>
                                            _confirmDelete(context, isEs),
                                        onDismissed: (_) => _delete(id),
                                        child: _buildCard(row, isEs,
                                            pinned: false),
                                      ),
                                    ),
                                  ],
                                );
                              },
                              childCount: _filteredAutoSaves.length,
                            ),
                          ),
                        ],
                      ],
                      const SliverToBoxAdapter(
                          child: SizedBox(height: AppSpacing.lg)),
                    ],
                  ),
                ),
        ),
        const CalcwiseAdFooter(),
      ],
    ));
  }

  Future<bool?> _confirmDelete(BuildContext context, bool isEs) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isEs ? '¿Eliminar entrada?' : 'Delete entry?'),
        content: Text(
            isEs ? '¿Eliminar este cálculo?' : 'Remove this calculation?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isEs ? 'Cancelar' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(isEs ? 'Eliminar' : 'Delete',
                style: TextStyle(
                    color: CalcwiseSemanticColors.error(
                        Theme.of(ctx).brightness))),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isEs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.xs),
      child: ValueListenableBuilder<bool>(
        valueListenable: freemiumService.hasFullAccessNotifier,
        builder: (_, isPremium, __) => ValueListenableBuilder<bool>(
          valueListenable: freemiumService.isRewardedNotifier,
          builder: (_, isRewarded, ___) {
            final unlocked = isPremium || isRewarded;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      unlocked
                          ? '${_history.length} ${isEs ? 'cálculos guardados' : 'entries saved'}'
                          : '${_autoSaves.length} / ${MonetizationConfig.freeRingBufferSize} ${isEs ? 'guardados' : 'saved'}',
                      style: const TextStyle(
                          color: AppTheme.labelGray, fontSize: AppTextSize.md),
                    ),
                  ),
                  if (unlocked && _history.isNotEmpty)
                    TextButton.icon(
                      onPressed: _clearAll,
                      icon: Icon(Icons.delete_sweep,
                          size: 16,
                          color: CalcwiseSemanticColors.error(
                              Theme.of(context).brightness)),
                      label: Text(
                        isEs ? 'Borrar todo' : 'Clear all',
                        style: TextStyle(
                            color: CalcwiseSemanticColors.error(
                                Theme.of(context).brightness),
                            fontSize: AppTextSize.md),
                      ),
                    ),
                ]),
                if (!unlocked) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(children: [
                    const Icon(Icons.lock_outline,
                        size: 13, color: CalcwiseSemanticColors.warnIcon),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        isEs
                            ? 'Máx. ${MonetizationConfig.freeRingBufferSize} entradas recientes (gratis)'
                            : 'Max ${MonetizationConfig.freeRingBufferSize} recent entries for free users',
                        style: const TextStyle(
                            fontSize: AppTextSize.sm, color: AppTheme.labelGray),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        PaywallSoft.show(context, isSpanish: isSpanishNotifier.value);
                      },
                      style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                      child: Text(
                        isEs ? 'Desbloquear' : 'Unlock',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontWeight: FontWeight.w600,
                            fontSize: AppTextSize.sm),
                      ),
                    ),
                  ]),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, AppSpacing.md, AppSpacing.xl, AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              fontSize: AppTextSize.xs,
              fontWeight: FontWeight.w700,
              color: AppTheme.primary,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row, bool isEs,
      {required bool pinned}) {
    final id = row['id'] as int;
    final inputs = row['inputs'] as Map<String, dynamic>;
    final results = row['results'] as Map<String, dynamic>;
    final createdAt = DateTime.parse(row['created_at'] as String);

    final isCalcShape = _isCalcShape(inputs);
    final draw = (inputs['draw'] as num?)?.toDouble() ?? 0.0;
    final rate = (inputs['rate'] as num?)?.toDouble() ?? 0.0;
    final equity = (results['equity'] as num?)?.toDouble() ?? 0.0;
    final interestOnly = (results['interestOnly'] as num?)?.toDouble() ?? 0.0;
    final pinLabel = row['pin_label'] as String?;
    final l1 = isCalcShape ? const <String, dynamic>{} : _decodeL1(row);
    final l1Entries = l1.entries.toList();

    final humanLabel = isCalcShape
        ? '${_shortK(draw)} ${isEs ? 'dispuesto' : 'draw'} @ ${rate.toStringAsFixed(1)}%'
        : (l1Entries.isNotEmpty
            ? '${l1Entries.first.key}: ${_fmtL1Value(l1Entries.first.value)}'
            : (isEs ? 'Escenario guardado' : 'Saved scenario'));
    final title = pinned && pinLabel != null && pinLabel.isNotEmpty
        ? pinLabel
        : humanLabel;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        side: pinned
            ? BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.5), width: 1.5)
            : BorderSide(
                color: AppTheme.primary.withValues(alpha: 0.18)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        onTap: () => HistoryDetailScreen.push(
          context,
          entry: row,
          onDelete: () => _delete(id),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.mdPlus, vertical: AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (pinned) ...[
                  const Icon(Icons.bookmark_rounded,
                      size: 16, color: AppTheme.primary),
                  const SizedBox(width: 5),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: AppTextSize.bodyMd,
                            color: AppTheme.primary),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmtDate.format(createdAt.toLocal()),
                        style: const TextStyle(
                            fontSize: AppTextSize.xs,
                            color: AppTheme.labelGray),
                      ),
                    ],
                  ),
                ),
                if (pinned)
                  SizedBox(
                    height: 28,
                    width: 32,
                    child: PopupMenuButton<_CardAction>(
                      icon: const Icon(Icons.more_vert_rounded,
                          size: 18, color: AppTheme.labelGray),
                      padding: EdgeInsets.zero,
                      onSelected: (action) {
                        switch (action) {
                          case _CardAction.unpin:
                            _unpin(id);
                          case _CardAction.rename:
                            _rename(row);
                          case _CardAction.delete:
                            _delete(id);
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _CardAction.unpin,
                          child: Row(children: [
                            const Icon(Icons.bookmark_remove_outlined, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text(isEs ? 'Desfijar' : 'Unpin'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: _CardAction.rename,
                          child: Row(children: [
                            const Icon(Icons.edit_outlined, size: 18),
                            const SizedBox(width: AppSpacing.sm),
                            Text(isEs ? 'Renombrar' : 'Rename'),
                          ]),
                        ),
                        PopupMenuItem(
                          value: _CardAction.delete,
                          child: Row(children: [
                            Icon(Icons.delete_outline_rounded,
                                size: 18,
                                color: CalcwiseSemanticColors.error(
                                    Theme.of(context).brightness)),
                            const SizedBox(width: AppSpacing.sm),
                            Text(isEs ? 'Eliminar' : 'Delete',
                                style: TextStyle(
                                    color: CalcwiseSemanticColors.error(
                                        Theme.of(context).brightness))),
                          ]),
                        ),
                      ],
                    ),
                  )
                else
                  const Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppTheme.labelGray),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCalcShape
                              ? (isEs ? 'Pago interés' : 'Interest pmt')
                              : (l1Entries.isNotEmpty
                                  ? l1Entries.first.key
                                  : ''),
                          style: const TextStyle(
                              fontSize: AppTextSize.xs,
                              color: AppTheme.labelGray),
                        ),
                        Text(
                          isCalcShape
                              ? '${AmountFormatter.ui(interestOnly, 'USD')}/${isEs ? 'mes' : 'mo'}'
                              : (l1Entries.isNotEmpty
                                  ? _fmtL1Value(l1Entries.first.value)
                                  : ''),
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: AppTextSize.bodyMd,
                              color: AppTheme.primary),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          isCalcShape
                              ? (isEs ? 'Capital disp.' : 'Equity')
                              : (l1Entries.length > 1
                                  ? l1Entries[1].key
                                  : ''),
                          style: const TextStyle(
                              fontSize: AppTextSize.xs,
                              color: AppTheme.labelGray),
                        ),
                        Text(
                          isCalcShape
                              ? AmountFormatter.ui(equity, 'USD')
                              : (l1Entries.length > 1
                                  ? _fmtL1Value(l1Entries[1].value)
                                  : ''),
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: AppTextSize.bodyMd,
                              color: AppTheme.success),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySkeleton extends StatelessWidget {
  const _HistorySkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: List.generate(
            3,
            (i) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.smPlus),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            _ShimmerBox(
                                width: 120, height: 26, radius: AppRadius.md),
                            const Spacer(),
                            _ShimmerBox(
                                width: 70, height: 22, radius: AppRadius.sm),
                          ]),
                          const SizedBox(height: 12),
                          ...List.generate(
                              4,
                              (_) => Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 5),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        _ShimmerBox(
                                            width: 100, height: 13, radius: 4),
                                        _ShimmerBox(
                                            width: 70, height: 13, radius: 4),
                                      ],
                                    ),
                                  )),
                        ],
                      ),
                    ),
                  ),
                )),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  final double width, height, radius;
  const _ShimmerBox(
      {required this.width, required this.height, required this.radius});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
