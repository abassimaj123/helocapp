import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart'
    hide CrashlyticsService, iapErrorNotifier, PaywallHard;
import 'core/ads/ad_config.dart';
import 'core/db/heloc_database_adapter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/firebase/analytics_service.dart';
import 'core/firebase/firebase_options.dart';
import 'core/freemium/freemium_service.dart';
import 'core/freemium/iap_service.dart';
import 'core/services/crashlytics_service.dart';
import 'core/theme/app_theme.dart';
import 'l10n/strings_en.dart';
import 'l10n/strings_es.dart';
import 'screens/calculator_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/draw_schedule_screen.dart';
import 'screens/heloc_vs_cashout_screen.dart';
import 'screens/history_screen.dart';
import 'screens/payment_shock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/tools_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/paywall_hard.dart';
import 'widgets/paywall_soft.dart';

final paywallSession = PaywallSessionService(
  appKey: 'helocapp',
  hasFullAccess: () => freemiumService.hasFullAccess,
);

final adService = CalcwiseAdService(
  config: CalcwiseAdConfig(
    bannerAndroid: AdConfig.bannerAndroid,
    interstitialAndroid: AdConfig.interstitialAndroid,
    rewardedAndroid: AdConfig.rewardedAndroid,
    calcThreshold: AdConfig.calcThreshold,
    cooldownMinutes: AdConfig.cooldownMinutes,
  ),
  freemium: freemiumService,
  analytics: AnalyticsService.instance,
);

final ValueNotifier<bool> isSpanishNotifier = ValueNotifier<bool>(false);

/// Smart history (auto-save ring buffer + pinned scenarios).
final smartHistoryService = SmartHistoryService(
  db: HelocDatabaseAdapter(),
  freemium: freemiumService,
);

/// Jump to a specific bottom-nav tab from anywhere (e.g. History empty state).
final ValueNotifier<int> tabSwitchNotifier = ValueNotifier<int>(-1);

/// Last-calculated HELOC values for pre-filling secondary tools.
final ValueNotifier<({double creditLimit, double balance, double rate})>
    helocNotifier =
    ValueNotifier((creditLimit: 100000.0, balance: 100000.0, rate: 7.5));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await AnalyticsService.instance.initialize();
  unawaited(CalcwiseRemoteConfig.initialize());
  await CalcwiseTax.init(remoteFetcher: calcwiseTaxRemoteFetch);
  await CrashlyticsService.init();
  await AnalyticsService.instance.logAppOpen();

  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  if (saved != null) {
    isSpanishNotifier.value = saved == 'es';
  } else {
    final locales = PlatformDispatcher.instance.locales;
    final lang = locales.isNotEmpty ? locales.first.languageCode : 'en';
    isSpanishNotifier.value = lang == 'es';
  }

  // statusBarIconBrightness is set dynamically in the shell build()
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));

  await themeModeService.initialize();
  await freemiumService.initialize();
  await IAPService.instance.initialize();
  await paywallSession.initialize();

  try {
    await requestCalcwiseConsent();
    if (AdConfig.adsEnabled) await adService.initialize(); // MobileAds.initialize() called internally
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        testDeviceIds: ['FD16D4616C3A21C3ACE5E48F8DC9C1DC'],
      ),
    );
  } catch (e) {
    debugPrint('AdMob init error: $e');
  }

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
    onGetPremium: () => IAPService.instance.buy(),
    analytics: AnalyticsService.instance,
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
  );
  PaywallHard.setAnalytics(AnalyticsService.instance);
  runApp(const _IapErrorWrapper());
}

class _IapErrorWrapper extends StatefulWidget {
  const _IapErrorWrapper();

  @override
  State<_IapErrorWrapper> createState() => _IapErrorWrapperState();
}

class _IapErrorWrapperState extends State<_IapErrorWrapper> {
  final _smKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    iapErrorNotifier.addListener(_onIapError);
    iapRestoreResultNotifier.addListener(_onRestoreResult);
  }

  @override
  void dispose() {
    iapErrorNotifier.removeListener(_onIapError);
    iapRestoreResultNotifier.removeListener(_onRestoreResult);
    super.dispose();
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _smKey.currentState?.showSnackBar(SnackBar(content: Text(msg)));
      iapErrorNotifier.value = null;
    });
  }

  void _onRestoreResult() {
    final result = iapRestoreResultNotifier.value;
    if (result == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final isEs = isSpanishNotifier.value;
      final msg = result == 'restored'
          ? (isEs ? '¡Premium restaurado!' : 'Premium restored!')
          : (isEs ? 'No hay compras para restaurar.' : 'No purchases to restore.');
      _smKey.currentState?.showSnackBar(
        SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
      );
      iapRestoreResultNotifier.value = null;
    });
  }

  @override
  Widget build(BuildContext context) => HELOCApp(smKey: _smKey);
}

class HELOCApp extends StatelessWidget {
  const HELOCApp({super.key, required this.smKey});
  final GlobalKey<ScaffoldMessengerState> smKey;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isEs, __) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeService.notifier,
          builder: (context, themeMode, child) => MaterialApp(
                scaffoldMessengerKey: smKey,
                title: isEs ? AppStringsES.appName : AppStringsEN.appName,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                debugShowCheckedModeBanner: false,
                builder: (context, child) {
                  if (!MediaQuery.of(context).disableAnimations) return child!;
                  return Theme(
                    data: Theme.of(context).copyWith(
                      pageTransitionsTheme: const PageTransitionsTheme(
                        builders: {
                          TargetPlatform.android:
                              _NoAnimPageTransitionsBuilder(),
                          TargetPlatform.iOS: _NoAnimPageTransitionsBuilder(),
                        },
                      ),
                    ),
                    child: child!,
                  );
                },
                home: const SplashScreen(),
                routes: {
                  '/home': (_) => const MainShell(),
                  '/payment-shock': (_) => const PaymentShockScreen(),
                  '/heloc-vs-cashout': (_) => const HelocVsCashoutScreen(),
                },
              ),
        );
      },
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  bool _wasPremium = false;

  static const List<Widget> _screens = [
    CalculatorScreen(),
    DrawScheduleScreen(),
    CompareScreen(),
    ToolsScreen(),
    HistoryScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    unawaited(AnalyticsService.instance.setUserPremium(freemiumService.hasFullAccess));
    isSpanishNotifier.addListener(_onLangChange);
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    tabSwitchNotifier.addListener(_onTabSwitch);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) async => await paywallSession.recordSession());
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    tabSwitchNotifier.removeListener(_onTabSwitch);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _onTabSwitch() {
    final idx = tabSwitchNotifier.value;
    if (idx >= 0 && mounted) {
      setState(() => _index = idx);
      tabSwitchNotifier.value = -1;
    }
  }

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: isSpanishNotifier.value);
      try { AnalyticsService.instance.logPaywallConverted('iap'); } catch (_) {}
    }
    _wasPremium = now;
    unawaited(AnalyticsService.instance.setUserPremium(now));
  }

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: CalcwiseTheme.of(context).surface,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? AppStringsES.appName : AppStringsEN.appName),
        actions: [
          CalcwiseAppBarActions(
            freemium: freemiumService,
            session: paywallSession,
            onSettings: () {
              AnalyticsService.instance.logScreenView('settings');
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => const SettingsScreen(),
                  transitionsBuilder: (_, anim, __, child) =>
                      FadeTransition(opacity: anim, child: child),
                  transitionDuration: AppDuration.base,
                ),
              );
            },
            onRewardAd: () => CalcwiseRewardAdSheet.show(context),
            onPremium: () {
              AnalyticsService.instance.logPaywallHardShown();
              PaywallHard.show(context);
            },
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: List.generate(
          _screens.length,
          (i) => IgnorePointer(
            ignoring: _index != i,
            child: CalcwiseTabReveal(active: _index == i, child: _screens[i]),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) async {
          if (i == _index) return;
          setState(() => _index = i);
          AnalyticsService.instance.logTabSwitched(tabIndex: i);
          adService.onAction();
          // Calculator tab (index 0) is always free — no action recording.
          if (i == 0) return;
          final trigger = await paywallSession.recordAction();
          if (trigger != PaywallTrigger.none &&
              mounted &&
              (ModalRoute.of(context)?.isCurrent ?? false) &&
              !freemiumService.hasFullAccess) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (trigger == PaywallTrigger.soft) {
                AnalyticsService.instance.logPaywallSoftShown();
                PaywallSoft.show(context);
              } else {
                AnalyticsService.instance.logPaywallHardShown();
                PaywallHard.show(context);
              }
            });
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_rounded),
            selectedIcon: const Icon(Icons.home_rounded),
            label: isEs ? AppStringsES.calculator : AppStringsEN.calculator,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timeline_rounded),
            selectedIcon: const Icon(Icons.timeline),
            label: isEs ? 'Calendario' : 'Draw Schedule',
          ),
          NavigationDestination(
            icon: const Icon(Icons.compare_arrows_rounded),
            selectedIcon: const Icon(Icons.compare_arrows),
            label: isEs ? 'Comparar' : 'Compare',
          ),
          NavigationDestination(
            icon: const Icon(Icons.build_rounded),
            selectedIcon: const Icon(Icons.build),
            label: isEs ? 'Herramientas' : 'Tools',
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_rounded),
            selectedIcon: const Icon(Icons.history),
            label: isEs ? AppStringsES.history : AppStringsEN.history,
          ),
        ],
      ),
    );
  }
}

class _NoAnimPageTransitionsBuilder extends PageTransitionsBuilder {
  const _NoAnimPageTransitionsBuilder();
  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}
