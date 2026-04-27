import 'package:flutter/material.dart';
import '../core/firebase/analytics_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../main.dart';

class PaywallSoft extends StatelessWidget {
  const PaywallSoft({super.key});

  static Future<void> show(BuildContext context) {
    AnalyticsService.instance.logPaywallShown(type: 'soft');
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const PaywallSoft(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isSpanish, __) {
        final title = isSpanish
            ? 'Toma mejores decisiones financieras'
            : 'Make smarter financial decisions';
        final sub = isSpanish
            ? 'Acceso completo — sin publicidad'
            : 'Unlock full access — no ads';
        final features = isSpanish
            ? ['📊 Historial ilimitado', '⚡ Resultados al instante', '🚫 Sin anuncios']
            : ['📊 Unlimited history', '⚡ Instant insights', '🚫 Zero ads forever'];
        const price = r'$2.99';
        final btnPrimary = isSpanish ? 'Desbloquear Premium\n$price' : 'Unlock Premium\n$price';
        final btnSecondary = isSpanish ? 'Más tarde' : 'Maybe later';

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
                    color: AppTheme.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.star_rounded, color: AppTheme.primary, size: 32),
                ),
                const SizedBox(height: 16),
                Text(title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () {
                    AnalyticsService.instance.logPaywallDismissed();
                    Navigator.pop(context);
                  },
                  child: Text(btnSecondary,
                      style: const TextStyle(color: AppTheme.labelGray, fontSize: 13)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
