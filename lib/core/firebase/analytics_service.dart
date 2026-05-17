import 'package:calcwise_core/calcwise_core.dart';

/// Firebase Analytics wrapper for HELOCApp.
/// Common events inherited from CalcwiseAnalytics.
/// HELOC-specific events (heloc_calculated, compare, draw schedule, soft/hard paywall) kept here.
class AnalyticsService extends CalcwiseAnalytics {
  AnalyticsService._() : super(appName: 'HELOCApp');
  static final AnalyticsService instance = AnalyticsService._();

  // ── Calculator (HELOC-specific) ───────────────────────────────────────────

  Future<void> logCalculation({
    required double homeValue,
    required double ratePct,
  }) =>
      log('heloc_calculated', {
        'home_value_bucket': _valueBucket(homeValue),
        'rate_bucket': _rateBucket(ratePct),
      });

  Future<void> logCompareViewed({
    double? withdrawalAmount,
    double? helocRate,
    double? refiRate,
  }) =>
      log('heloc_compare_viewed', {
        if (withdrawalAmount != null)
          'withdrawal_bucket': _valueBucket(withdrawalAmount),
        if (helocRate != null) 'heloc_rate_bucket': _rateBucket(helocRate),
        if (refiRate != null) 'refi_rate_bucket': _rateBucket(refiRate),
      });

  Future<void> logTabSwitched({required int tabIndex}) =>
      log('tab_switched', {'tab_index': tabIndex});

  Future<void> logDrawScheduleViewed() => log('draw_schedule_viewed');

  // ── Paywall variants ──────────────────────────────────────────────────────

  Future<void> logPaywallSoftShown() => log('paywall_soft_shown');
  Future<void> logPaywallHardShown() => log('paywall_hard_shown');

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _valueBucket(double v) {
    if (v < 100000) return '<100k';
    if (v < 300000) return '100k-300k';
    if (v < 500000) return '300k-500k';
    if (v < 1000000) return '500k-1M';
    return '>1M';
  }

  String _rateBucket(double r) {
    if (r < 3) return '<3%';
    if (r < 5) return '3-5%';
    if (r < 7) return '5-7%';
    if (r < 10) return '7-10%';
    return '>10%';
  }
}
