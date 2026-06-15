import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/material.dart';
import '../core/firebase/analytics_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart' show isSpanishNotifier;
import 'draw_optimizer_screen.dart';
import 'heloc_vs_cashout_screen.dart';
import 'payment_shock_screen.dart';

const _toolTealColor = Color(0xFF00897B);
const _toolOrangeColor = Color(0xFFF57C00);
const _toolIndigoColor = Color(0xFF5C6BC0);

class ToolsScreen extends StatefulWidget {
  const ToolsScreen({super.key});

  @override
  State<ToolsScreen> createState() => _ToolsScreenState();
}

class _ToolsScreenState extends State<ToolsScreen> {
  @override
  void initState() {
    super.initState();
    AnalyticsService.instance.logScreenView('tools');
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (context, isEs, _) {
        return Scaffold(
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    _ToolCard(
                      icon: Icons.tune_rounded,
                      color: _toolTealColor,
                      title: isEs ? 'Optimizador de retiro' : 'Draw Optimizer',
                      subtitle: isEs
                          ? 'Optimice su calendario de retiro'
                          : 'Optimize your draw schedule',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DrawOptimizerScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ToolCard(
                      icon: Icons.trending_up_rounded,
                      color: _toolOrangeColor,
                      title: isEs ? 'Choque de pago' : 'Payment Shock',
                      subtitle: isEs
                          ? 'Vea cómo cambian los pagos después del período de retiro'
                          : 'See how payments change after draw period',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PaymentShockScreen(),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _ToolCard(
                      icon: Icons.compare_arrows_rounded,
                      color: _toolIndigoColor,
                      title: isEs ? 'HELOC vs Refinanciamiento' : 'HELOC vs Cash-Out Refi',
                      subtitle: isEs
                          ? 'Compare HELOC con refinanciamiento con retiro de efectivo'
                          : 'Compare HELOC with cash-out refinance',
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const HelocVsCashoutScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const CalcwiseAdFooter(),
            ],
          ),
        );
      },
    );
  }
}

class _ToolCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ToolCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedCornerShape(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: AppTextSize.bodyMd,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: AppTextSize.sm,
                        color: CalcwiseTheme.of(context).textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: CalcwiseTheme.of(context).textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RoundedCornerShape extends RoundedRectangleBorder {
  RoundedCornerShape(double radius)
      : super(borderRadius: BorderRadius.circular(radius));
}
