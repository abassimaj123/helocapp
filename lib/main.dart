import 'package:calcwise_core/calcwise_core.dart'
    hide CrashlyticsService, iapErrorNotifier;
import 'core/ads/ad_config.dart';
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
import 'l10n/strings_fr.dart';
import 'screens/calculator_screen.dart';
import 'screens/compare_screen.dart';
import 'screens/draw_schedule_screen.dart';
import 'screens/heloc_vs_cashout_screen.dart';
import 'screens/history_screen.dart';
import 'screens/payment_shock_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/paywall_hard.dart';
import 'widgets/paywall_soft.dart';

final paywallSession = PaywallSessionService(appKey: 'helocapp');

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
final ValueNotifier<bool> isFrenchNotifier = ValueNotifier<bool>(false);

/// Last-calculated HELOC values for pre-filling secondary tools.
final ValueNotifier<({double creditLimit, double balance, double rate})>
    helocNotifier = ValueNotifier(
        (creditLimit: 100000.0, balance: 100000.0, rate: 8.5));

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await CrashlyticsService.init();
  await AnalyticsService.instance.logAppOpen();

  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString('language');
  if (saved != null) {
    isSpanishNotifier.value = saved == 'es';
    isFrenchNotifier.value = saved == 'fr';
  } else {
    final locales = PlatformDispatcher.instance.locales;
    final lang = locales.isNotEmpty ? locales.first.languageCode : 'en';
    isSpanishNotifier.value = lang == 'es';
    isFrenchNotifier.value = lang == 'fr';
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
    await MobileAds.instance.initialize();
    if (AdConfig.adsEnabled) await adService.initialize();
  } catch (e) {
    debugPrint('AdMob init error: $e');
  }

  CalcwiseAdFooter.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
    onGetPremium: () => IAPService.instance.buy(),
  );
  CalcwiseRewardAdSheet.configure(
    adService: adService,
    freemium: freemiumService,
    isSpanishNotifier: isSpanishNotifier,
  );
  runApp(const _IapErrorWrapper());
}

class _IapErrorWrapper extends StatefulWidget {
  const _IapErrorWrapper();

  @override
  State<_IapErrorWrapper> createState() => _IapErrorWrapperState();
}

class _IapErrorWrapperState extends State<_IapErrorWrapper> {
  @override
  void initState() {
    super.initState();
    iapErrorNotifier.addListener(_onIapError);
  }

  @override
  void dispose() {
    iapErrorNotifier.removeListener(_onIapError);
    super.dispose();
  }

  void _onIapError() {
    final msg = iapErrorNotifier.value;
    if (msg == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      iapErrorNotifier.value = null;
    });
  }

  @override
  Widget build(BuildContext context) => const HELOCApp();
}

class HELOCApp extends StatelessWidget {
  const HELOCApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isEs, __) {
        return ValueListenableBuilder<bool>(
          valueListenable: isFrenchNotifier,
          builder: (_, isFr, __) {
            return ValueListenableBuilder<ThemeMode>(
              valueListenable: themeModeService.notifier,
              builder: (context, themeMode, child) => MaterialApp(
                title: isFr
                    ? AppStringsFR.appName
                    : (isEs ? AppStringsES.appName : AppStringsEN.appName),
                theme: AppTheme.theme,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                debugShowCheckedModeBanner: false,
                builder: (context, child) {
                  if (!MediaQuery.of(context).disableAnimations) return child!;
                  return Theme(
                    data: Theme.of(context).copyWith(
                      pageTransitionsTheme: const PageTransitionsTheme(
                        builders: {
                          TargetPlatform.android: _NoAnimPageTransitionsBuilder(),
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

  @override
  void initState() {
    super.initState();
    _wasPremium = freemiumService.hasFullAccess;
    isSpanishNotifier.addListener(_onLangChange);
    isFrenchNotifier.addListener(_onLangChange);
    freemiumService.isPremiumNotifier.addListener(_onPremiumChange);
    WidgetsBinding.instance.addPostFrameCallback(
        (_) async => await paywallSession.recordSession());
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    isFrenchNotifier.removeListener(_onLangChange);
    freemiumService.isPremiumNotifier.removeListener(_onPremiumChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  void _onPremiumChange() {
    final now = freemiumService.hasFullAccess;
    if (now && !_wasPremium && mounted) {
      showPremiumWelcomeSnackBar(context, isSpanish: isSpanishNotifier.value);
    }
    _wasPremium = now;
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
            onSettings: () => Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => const SettingsScreen(),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: AppDuration.base,
              ),
            ),
            onRewardAd: () => CalcwiseRewardAdSheet.show(context),
            onPremium: () => PaywallHard.show(context),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          CalculatorScreen(),
          DrawScheduleScreen(),
          CompareScreen(),
          HistoryScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) async {
          if (i == _index) return;
          setState(() => _index = i);
          AnalyticsService.instance.logTabSwitched(tabIndex: i);
          final trigger = await paywallSession.recordAction();
          if (trigger != PaywallTrigger.none &&
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
