import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final freemiumService = FreemiumService._();

class FreemiumService {
  FreemiumService._();

  static const _keyPremium       = 'is_premium';
  static const _keyRewarded      = 'rewarded_until';
  static const _keyRewardedDay   = 'rewarded_day';
  static const _keyRewardedCount = 'rewarded_count';

  static const int freeHistoryLimit  = 5;
  static const int rewardedMinutes   = 60;
  static const int maxRewardedPerDay = 2;

  late SharedPreferences _prefs;
  Timer? _timer;

  final isPremiumNotifier  = ValueNotifier<bool>(false);
  final isRewardedNotifier = ValueNotifier<bool>(false);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = _prefs.getBool(_keyPremium) ?? false;
    _refreshRewarded();
    _timer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshRewarded(),
    );
  }

  void _refreshRewarded() {
    final s = _prefs.getString(_keyRewarded);
    isRewardedNotifier.value =
        s != null && DateTime.now().isBefore(DateTime.parse(s));
  }

  bool get isPremium  => isPremiumNotifier.value;
  bool get isRewarded { _refreshRewarded(); return isRewardedNotifier.value; }

  bool get showAds => !isPremium && !isRewarded;

  int get historyLimit => isPremium ? 999999 : freeHistoryLimit;

  int get rewardedMinutesLeft {
    _refreshRewarded();
    if (!isRewardedNotifier.value) return 0;
    final s = _prefs.getString(_keyRewarded)!;
    return DateTime.parse(s)
        .difference(DateTime.now())
        .inMinutes
        .clamp(0, rewardedMinutes);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<int> _todayCount() async {
    final day = _prefs.getString(_keyRewardedDay);
    if (day != _todayKey()) return 0;
    return _prefs.getInt(_keyRewardedCount) ?? 0;
  }

  /// Returns false if already rewarded (active session), already premium,
  /// or daily cap (maxRewardedPerDay) reached.
  Future<bool> canWatchRewarded() async {
    if (isPremium || isRewarded) return false;
    final count = await _todayCount();
    return count < maxRewardedPerDay;
  }

  Future<void> activateRewarded() async {
    final today = _todayKey();
    final day   = _prefs.getString(_keyRewardedDay);
    final count = day == today ? (_prefs.getInt(_keyRewardedCount) ?? 0) : 0;
    await _prefs.setString(_keyRewardedDay,   today);
    await _prefs.setInt(_keyRewardedCount, count + 1);
    await _prefs.setString(
      _keyRewarded,
      DateTime.now()
          .add(const Duration(minutes: rewardedMinutes))
          .toIso8601String(),
    );
    isRewardedNotifier.value = true;
  }

  Future<void> activatePremium() async {
    isPremiumNotifier.value = true;
    await _prefs.setBool(_keyPremium, true);
    _timer?.cancel();
  }

  void debugUnlockPremium() {
    if (kDebugMode) activatePremium();
  }

  void dispose() => _timer?.cancel();
}
