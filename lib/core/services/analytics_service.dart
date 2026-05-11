import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Centralized Firebase Analytics wrapper for HELOCApp.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _fa = FirebaseAnalytics.instance;

  // ── Lifecycle ─────────────────────────────────────────────────────────────

  Future<void> logAppOpen() => _log('app_open');

  // ── Navigation ────────────────────────────────────────────────────────────

  Future<void> logTabChanged(String tabName) => _log('tab_changed', {
    'tab': tabName, // calculator|draw_phase|repayment|compare
  });

  // ── Calculator ────────────────────────────────────────────────────────────

  Future<void> logCalculation({
    required double homeValue,
    required double creditLine,
    required double rate,
  }) => _log('calculate', {
    'home_value_bucket': _valueBucket(homeValue),
    'credit_line_bucket': _valueBucket(creditLine),
    'rate_bucket': rate < 6 ? '<6%' : rate < 9 ? '6-9%' : '>9%',
  });

  // ── Paywall ───────────────────────────────────────────────────────────────

  Future<void> logPaywallShown(String type) => _log('paywall_shown', {'type': type});
  Future<void> logPurchaseStarted()         => _log('purchase_started');

  Future<void> logPurchaseCompleted() async {
    await _log('purchase_completed');
    await _fa.logEvent(name: 'purchase', parameters: {
      'currency': 'USD',
      'value':    2.99,
      'items':    'premium_heloc_app',
    });
  }

  Future<void> logPurchaseRestored()   => _log('purchase_restored');
  Future<void> logPurchaseFailed()     => _log('purchase_failed');
  Future<void> logRewardedAdWatched()  => _log('rewarded_ad_watched');

  // ── Features ─────────────────────────────────────────────────────────────

  Future<void> logPdfExported()       => _log('pdf_exported');
  Future<void> logScenarioCompared()  => _log('scenario_compared');
  Future<void> logHistorySaved()      => _log('history_saved');

  // ── User property ─────────────────────────────────────────────────────────

  Future<void> setUserPremium(bool isPremium) =>
      _fa.setUserProperty(name: 'is_premium', value: isPremium ? 'true' : 'false');

  // ── Error & limit tracking ────────────────────────────────────────────────

  Future<void> logRewardedAdFailed() => _log('rewarded_ad_failed');
  Future<void> logPaywallDismissed() => _log('paywall_dismissed');
  Future<void> logBannerFailed()     => _log('banner_ad_failed');

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    final merged = <String, Object>{'app_name': 'HELOCApp', ...?params};
    if (kDebugMode) {
      debugPrint('[Analytics] $name $merged');
      return;
    }
    await _fa.logEvent(name: name, parameters: merged);
  }

  String _valueBucket(double value) {
    if (value < 100000)  return '<100k';
    if (value < 300000)  return '100-300k';
    if (value < 600000)  return '300-600k';
    if (value < 1000000) return '600k-1M';
    return '>1M';
  }
}
