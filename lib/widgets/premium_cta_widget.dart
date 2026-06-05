import 'package:flutter/material.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import 'package:calcwise_core/calcwise_core.dart';

class PremiumCtaWidget extends StatelessWidget {
  final String feature;
  final bool compact;
  const PremiumCtaWidget(
      {super.key, required this.feature, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: AppTheme.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primary.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => IAPService.instance.buy(),
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : 20),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.smPlus),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: const Icon(Icons.star_rounded,
                    color: Colors.white, size: 26),
              ),
              const SizedBox(width: AppSpacing.mdPlus),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Unlock $feature',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTextSize.bodyMd,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: AppSpacing.xxs),
                  const Text('No ads · Unlimited · PDF export',
                      style: TextStyle(
                          color: Colors.white70, fontSize: AppTextSize.sm)),
                ],
              )),
              ValueListenableBuilder<String?>(
                valueListenable: IAPService.instance.localizedPrice,
                builder: (_, price, __) => Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.mdPlus, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(AppRadius.xxl)),
                  child: Text(price ?? '',
                      style: TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: AppTextSize.md)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
