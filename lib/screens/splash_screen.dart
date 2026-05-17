import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';
import '../core/firebase/analytics_service.dart';
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    try {
      AnalyticsService.instance.logAppOpen();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => CalcwiseSplash(
        appName: 'HELOC',
        tagline: 'Unlock your home equity',
        chips: const ['Credit Line', 'Draw Period', 'Repayment'],
        badgeSymbol: r'H$',
        badgeIcon: Icons.home_work_rounded,
        backgroundColor: AppTheme.primary,
        onComplete: () async {
          final done = await isOnboardingComplete('helocapp');
          if (!context.mounted) return;
          if (!done) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const OnboardingScreen()),
            );
          } else {
            Navigator.of(context).pushReplacementNamed('/home');
          }
        },
      );
}
