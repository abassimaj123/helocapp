import 'dart:async';
import 'package:calcwise_core/calcwise_core.dart' hide CrashlyticsService, iapErrorNotifier;
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/ads/ad_service.dart';
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
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'widgets/paywall_hard.dart';
import 'widgets/paywall_soft.dart';

final paywallSession = PaywallSessionService(appKey: 'helocapp');

final ValueNotifier<bool> isSpanishNotifier = ValueNotifier<bool>(false);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0B1E),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  await themeModeService.initialize();
  await freemiumService.initialize();
  await IAPService.instance.initialize();
  await paywallSession.initialize();

  try {
    await _requestConsent();
    await MobileAds.instance.initialize();
    await AdService.instance.initialize();
  } catch (e) {
    debugPrint('AdMob init error: $e');
  }

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
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
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeService.notifier,
          builder: (context, themeMode, child) => MaterialApp(
            title: isEs ? AppStringsES.appName : AppStringsEN.appName,
            theme: AppTheme.theme,
            darkTheme: AppTheme.dark,
            themeMode: themeMode,
            debugShowCheckedModeBanner: false,
            home: const SplashScreen(),
            routes: {
              '/home': (_) => const MainShell(),
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

  @override
  void initState() {
    super.initState();
    isSpanishNotifier.addListener(_onLangChange);
    WidgetsBinding.instance.addPostFrameCallback((_) async => await paywallSession.recordSession());
  }

  @override
  void dispose() {
    isSpanishNotifier.removeListener(_onLangChange);
    super.dispose();
  }

  void _onLangChange() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      systemNavigationBarColor: CalcwiseTheme.of(context).surface,
      systemNavigationBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
    ));

    return Scaffold(
      appBar: AppBar(
        title: Text(isEs ? AppStringsES.appName : AppStringsEN.appName),
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          CalculatorScreen(),
          DrawScheduleScreen(),
          CompareScreen(),
          SettingsScreen(),
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
          if (trigger != PaywallTrigger.none && !freemiumService.isPremium) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (trigger == PaywallTrigger.soft) {
                PaywallSoft.show(context);
              } else {
                PaywallHard.show(context);
              }
            });
          }
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: isEs ? AppStringsES.calculator : AppStringsEN.calculator,
          ),
          NavigationDestination(
            icon: const Icon(Icons.timeline_outlined),
            selectedIcon: const Icon(Icons.timeline),
            label: isEs ? 'Calendario' : 'Draw Schedule',
          ),
          NavigationDestination(
            icon: const Icon(Icons.compare_arrows_outlined),
            selectedIcon: const Icon(Icons.compare_arrows),
            label: isEs ? 'Comparar' : 'Compare',
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: isEs ? AppStringsES.settings : AppStringsEN.settings,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history_outlined),
            selectedIcon: const Icon(Icons.history),
            label: isEs ? AppStringsES.history : AppStringsEN.history,
          ),
        ],
      ),
    );
  }
}


/// Request GDPR/PIPEDA consent via Google UMP SDK.
/// Resolves on success, timeout, or error so the app always launches.
/// On non-EEA/UK devices the UMP SDK completes immediately without showing a form.
Future<void> _requestConsent() async {
  final completer = Completer<void>();
  ConsentInformation.instance.requestConsentInfoUpdate(
    ConsentRequestParameters(),
    () async {
      // Consent info updated — show form only if required
      if (await ConsentInformation.instance.isConsentFormAvailable()) {
        ConsentForm.loadAndShowConsentFormIfRequired(
          (_) { if (!completer.isCompleted) completer.complete(); },
        );
      } else {
        if (!completer.isCompleted) completer.complete();
      }
    },
    (_) { if (!completer.isCompleted) completer.complete(); },
  );
  return completer.future;
}
