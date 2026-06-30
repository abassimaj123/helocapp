import 'package:flutter/material.dart';
import 'package:calcwise_core/calcwise_core.dart';
import '../core/theme/app_theme.dart';
import '../main.dart' show isSpanishNotifier;
import 'onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  Widget build(BuildContext context) {
    final isEs = isSpanishNotifier.value;
    return CalcwiseSplash(
        appName: 'HELOC',
        tagline: isEs ? 'Libera el valor de tu hogar' : 'Unlock your home equity',
        chips: isEs
            ? const ['Línea de crédito', 'Período de disposición', 'Pago']
            : const ['Credit Line', 'Draw Period', 'Repayment'],
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
}
