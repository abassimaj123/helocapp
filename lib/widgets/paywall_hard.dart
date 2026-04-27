import 'package:flutter/material.dart';
import '../core/ads/ad_service.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';

class PaywallHard extends StatelessWidget {
  const PaywallHard({super.key});

  static Future<void> show(BuildContext context) {
    AnalyticsService.instance.logPaywallShown(type: 'hard');
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PaywallHard(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isSpanish, __) {
        final title = isSpanish
            ? 'No dejes que los costos te cuesten miles \$'
            : 'Don\'t let costs drain your savings';
        final sub = isSpanish
            ? 'Premium revela cómo ahorrar más'
            : 'Premium shows exactly how to save more';
        final features = isSpanish
            ? [
                '💰 Compara múltiples escenarios',
                '📉 Estrategia de optimización automática',
                '📊 Historial ilimitado & exportar PDF',
                '🚫 Sin anuncios — nunca',
              ]
            : [
                '💰 Compare multiple scenarios side by side',
                '📉 Automatic optimization strategy',
                '📊 Unlimited history & PDF export',
                '🚫 Zero ads — ever',
              ];
        const price = r'$2.99';
        const savings = r'(save $100+)';
        final btnPrimary = isSpanish
            ? 'Empezar a ahorrar\n$price (ahorra \$100+)'
            : 'Start saving now\n$price $savings';
        final btnReward = isSpanish ? 'Ver anuncio (60 min gratis)' : 'Watch ad (60 min free)';
        final btnSecondary = isSpanish ? 'Ahora no' : 'Not now';

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.trending_up_rounded, color: Colors.orange, size: 32),
                ),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                const SizedBox(height: 6),
                Text(sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 13, color: AppTheme.labelGray)),
                const SizedBox(height: 18),
                ...features.map((f) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Row(children: [
                        const SizedBox(width: 8),
                        Expanded(child: Text(f, style: const TextStyle(fontSize: 14))),
                      ]),
                    )),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      IAPService.instance.buy();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(btnPrimary,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold, height: 1.4)),
                  ),
                ),
                const SizedBox(height: 8),
                if (AdService.instance.isRewardedReady)
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        AdService.instance.showRewarded().then((earned) {
                          if (earned) freemiumService.activateRewarded();
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(btnReward, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                const SizedBox(height: 4),
                Opacity(
                  opacity: 0.5,
                  child: TextButton(
                    onPressed: () {
                      AnalyticsService.instance.logPaywallDismissed();
                      Navigator.pop(context);
                    },
                    child: Text(btnSecondary,
                        style: const TextStyle(color: AppTheme.labelGray, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
