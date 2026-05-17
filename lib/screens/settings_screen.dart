import 'package:calcwise_core/calcwise_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/freemium/freemium_service.dart';
import '../core/freemium/iap_service.dart';
import '../core/theme/app_theme.dart';
import '../l10n/strings_en.dart';
import '../l10n/strings_es.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setLanguage(bool isSpanish) async {
    isSpanishNotifier.value = isSpanish;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', isSpanish ? 'es' : 'en');
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSpanishNotifier,
      builder: (_, isEs, __) {
        return Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  // Language
                  _SectionHeader(
                      isEs ? 'IDIOMA / LANGUAGE' : 'LANGUAGE / IDIOMA'),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(children: [
                      Expanded(
                        child: _LangButton(
                          label: 'English',
                          selected: !isEs,
                          onTap: () => _setLanguage(false),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LangButton(
                          label: 'Español',
                          selected: isEs,
                          onTap: () => _setLanguage(true),
                        ),
                      ),
                    ]),
                  ),
                  // Theme toggle
                  ValueListenableBuilder<ThemeMode>(
                    valueListenable: themeModeService.notifier,
                    builder: (_, mode, __) => ListTile(
                      leading:
                          Icon(themeModeService.icon, color: AppTheme.primary),
                      title: Text(themeModeService.label(isSpanish: isEs)),
                      trailing: const Icon(Icons.chevron_right_rounded,
                          color: AppTheme.labelGray),
                      onTap: () => themeModeService.toggle(),
                    ),
                  ),
                  const Divider(height: 1),

                  // Premium
                  _SectionHeader(isEs
                      ? AppStringsES.premium.toUpperCase()
                      : AppStringsEN.premium.toUpperCase()),
                  ValueListenableBuilder<bool>(
                    valueListenable: freemiumService.isPremiumNotifier,
                    builder: (_, isPremium, __) {
                      if (isPremium) {
                        return ListTile(
                          leading: const Icon(Icons.verified_rounded,
                              color: Colors.amber),
                          title: Text(isEs
                              ? AppStringsES.premiumActive
                              : AppStringsEN.premiumActive),
                          subtitle: Text(isEs
                              ? AppStringsES.premiumDesc
                              : AppStringsEN.premiumDesc),
                        );
                      }
                      return Column(mainAxisSize: MainAxisSize.min, children: [
                        ListTile(
                          leading: const Icon(Icons.star_outline),
                          title: Text(isEs
                              ? '${AppStringsES.getPremium} — \$2.99'
                              : '${AppStringsEN.getPremium} — \$2.99'),
                          subtitle: Text(isEs
                              ? AppStringsES.premiumDesc
                              : AppStringsEN.premiumDesc),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppTheme.labelGray),
                          onTap: () => IAPService.instance.buy(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.restore),
                          title: Text(isEs
                              ? AppStringsES.restorePurchase
                              : AppStringsEN.restorePurchase),
                          onTap: () => IAPService.instance.restore(),
                        ),
                        ListTile(
                          leading: const Icon(Icons.play_circle_outline,
                              color: AppTheme.primary),
                          title: Text(isEs
                              ? 'Sin anuncios 60 min'
                              : 'Ad-free for 60 min'),
                          subtitle: Text(isEs
                              ? 'Ver un anuncio para desbloquear'
                              : 'Watch an ad to unlock'),
                          onTap: () async {
                            final earned = await adService.showRewarded();
                            if (earned) freemiumService.activateRewarded();
                            if (!earned && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isEs
                                      ? 'Anuncio no disponible'
                                      : 'Ad not available'),
                                ),
                              );
                            }
                          },
                        ),
                        if (kDebugMode)
                          ListTile(
                            leading: const Icon(Icons.bug_report,
                                color: Colors.orange),
                            title: const Text('Force Premium (DEV)'),
                            onTap: () => freemiumService.debugUnlockPremium(),
                          ),
                      ]);
                    },
                  ),
                  const Divider(height: 1),

                  // Support
                  _SectionHeader(isEs ? 'SOPORTE' : 'SUPPORT'),
                  _SettingsTile(
                    icon: Icons.privacy_tip_rounded,
                    label: isEs
                        ? AppStringsES.privacyPolicy
                        : AppStringsEN.privacyPolicy,
                    onTap: () => _launch('https://calqwise.com/privacy'),
                  ),
                  CalcwiseRateAppTile(
                      label: isEs ? 'Calificar la app' : 'Rate the App'),
                  _SettingsTile(
                    icon: Icons.email_rounded,
                    label: isEs
                        ? AppStringsES.contactSupport
                        : AppStringsEN.contactSupport,
                    onTap: () => _launch('mailto:support@calqwise.com'),
                  ),
                  const Divider(height: 1),

                  // Discover
                  _SectionHeader(isEs
                      ? AppStringsES.discover.toUpperCase()
                      : AppStringsEN.discover.toUpperCase()),
                  _SettingsTile(
                    icon: Icons.apps_rounded,
                    label: 'CalqWise',
                    subtitle:
                        isEs ? AppStringsES.calqwise : AppStringsEN.calqwise,
                    onTap: () => _launch('https://calqwise.com'),
                  ),
                  _SettingsTile(
                    icon: Icons.grid_view_rounded,
                    label:
                        isEs ? 'Más apps de CalqWise' : 'More apps by CalqWise',
                    subtitle: isEs
                        ? 'Ver todas nuestras calculadoras'
                        : 'See all our calculators',
                    onTap: () => _launch(
                        'https://play.google.com/store/apps/developer?id=CalqWise'),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Text(
                      isEs ? AppStringsES.disclaimer : AppStringsEN.disclaimer,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF475569),
                            fontStyle: FontStyle.italic,
                          ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            const CalcwiseAdFooter(),
          ],
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: AppTextSize.xs,
            fontWeight: FontWeight.w600,
            color: AppTheme.primary,
            letterSpacing: 0.8,
          ),
        ),
      );
}

class _LangButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangButton(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: AppDuration.fast,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primary : Colors.transparent,
            border: Border.all(
                color: selected ? AppTheme.primary : const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurface,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  const _SettingsTile(
      {required this.icon,
      required this.label,
      this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppTheme.primary),
        title: Text(label),
        subtitle: subtitle != null ? Text(subtitle!) : null,
        trailing: const Icon(Icons.chevron_right_rounded,
            size: 18, color: AppTheme.labelGray),
        onTap: onTap,
      );
}
