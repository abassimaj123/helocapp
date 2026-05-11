import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

class AnalyticsService {
  AnalyticsService._();
  static final instance = AnalyticsService._();

  final _a = FirebaseAnalytics.instance;

  Future<void> logCalculation({
    required double homeValue,
    required double ratePct,
  }) async {
    if (kDebugMode) return;
    await _log('heloc_calculated', {
      'home_value_bucket': _valueBucket(homeValue),
      'rate_bucket': _rateBucket(ratePct),
    });
  }

  Future<void> logCompareViewed({
    double? withdrawalAmount,
    double? helocRate,
    double? refiRate,
  }) async {
    if (kDebugMode) return;
    await _log('heloc_compare_viewed', {
      if (withdrawalAmount != null)
        'withdrawal_bucket': _valueBucket(withdrawalAmount),
      if (helocRate != null) 'heloc_rate_bucket': _rateBucket(helocRate),
      if (refiRate != null) 'refi_rate_bucket': _rateBucket(refiRate),
    });
  }

  Future<void> logTabSwitched({required int tabIndex}) async {
    if (kDebugMode) return;
    await _log('tab_switched', {'tab_index': tabIndex});
  }

  Future<void> logDrawScheduleViewed() async {
    if (kDebugMode) return;
    await _log('draw_schedule_viewed');
  }

  Future<void> logHistorySaved() async {
    if (kDebugMode) return;
    await _log('history_saved');
  }

  Future<void> logHistoryViewed() async {
    if (kDebugMode) return;
    await _log('history_viewed');
  }

  Future<void> logPdfExported() async {
    if (kDebugMode) return;
    await _log('pdf_exported');
  }

  Future<void> logRewardedAdWatched() async {
    if (kDebugMode) return;
    await _log('rewarded_ad_watched');
  }

  Future<void> logPurchased() async {
    if (kDebugMode) return;
    await _log('premium_purchased');
  }

  Future<void> logRestored() async {
    if (kDebugMode) return;
    await _log('premium_restored');
  }

  Future<void> logAppOpen() async {
    if (kDebugMode) return;
    await _a.logAppOpen();
  }

  Future<void> logPaywallSoftShown() async {
    if (kDebugMode) return;
    await _log('paywall_soft_shown');
  }

  Future<void> logPaywallHardShown() async {
    if (kDebugMode) return;
    await _log('paywall_hard_shown');
  }

  Future<void> logPaywallShown({required String type}) async {
    if (kDebugMode) return;
    await _log('paywall_shown', {'type': type});
  }

  Future<void> logPaywallDismissed() async {
    if (kDebugMode) return;
    await _log('paywall_dismissed');
  }

  Future<void> logPurchaseStarted() async {
    if (kDebugMode) return;
    await _log('iap_purchase_started');
  }

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

  // ── Error & limit tracking ──────────────────────────────────────────────
  Future<void> logRewardedAdFailed() async { if (!kDebugMode) await _log('rewarded_ad_failed'); }
  Future<void> logRewardedDailyLimit() async { if (!kDebugMode) await _log('rewarded_daily_limit_reached'); }
  Future<void> logPurchaseFailed() async { if (!kDebugMode) await _log('purchase_failed'); }
  Future<void> logBannerFailed() async { if (!kDebugMode) await _log('banner_ad_failed'); }

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    try {
      await _a.logEvent(name: name, parameters: {'app_name': 'HELOCApp', ...?params});
    } catch (e) {
      debugPrint('Analytics $name: $e');
    }
  }
}
