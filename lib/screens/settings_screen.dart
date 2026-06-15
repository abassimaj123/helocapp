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
import '../l10n/strings_fr.dart';
import '../main.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _setLanguage(String lang) async {
    isSpanishNotifier.value = lang == 'es';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language', lang);
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
        return ValueListenableBuilder<bool>(
          valueListenable: isFrenchNotifier,
          builder: (_, isFr, __) {
            final headerLabel = isFr
                ? 'LANGUE / LANGUAGE'
                : (isEs ? 'IDIOMA / LANGUAGE' : 'LANGUAGE / IDIOMA');
            return Column(
              children: [
                Expanded(
                  child: ListView(
                    children: [
                      // Premium
                      _SectionHeader(isFr
                          ? AppStringsFR.premium.toUpperCase()
                          : (isEs
                              ? AppStringsES.premium.toUpperCase()
                              : AppStringsEN.premium.toUpperCase())),
                      ValueListenableBuilder<bool>(
                        valueListenable: freemiumService.hasFullAccessNotifier,
                        builder: (_, isPremium, __) {
                          if (isPremium) {
                            return ListTile(
                              leading: const Icon(Icons.verified_rounded,
                                  color: CalcwiseSemanticColors.warnIcon),
                              title: Text(isFr
                                  ? AppStringsFR.premiumActive
                                  : (isEs
                                      ? AppStringsES.premiumActive
                                      : AppStringsEN.premiumActive)),
                              subtitle: Text(isFr
                                  ? AppStringsFR.premiumDesc
                                  : (isEs
                                      ? AppStringsES.premiumDesc
                                      : AppStringsEN.premiumDesc)),
                            );
                          }
                          return Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ListTile(
                                  leading: const Icon(Icons.star_outline),
                                  title: Text(isFr
                                      ? AppStringsFR.getPremium
                                      : (isEs
                                          ? AppStringsES.getPremium
                                          : AppStringsEN.getPremium)),
                                  subtitle: Text(isFr
                                      ? AppStringsFR.premiumDesc
                                      : (isEs
                                          ? AppStringsES.premiumDesc
                                          : AppStringsEN.premiumDesc)),
                                  trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: AppTheme.labelGray),
                                  onTap: () => IAPService.instance.buy(),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.restore),
                                  title: Text(isFr
                                      ? AppStringsFR.restorePurchase
                                      : (isEs
                                          ? AppStringsES.restorePurchase
                                          : AppStringsEN.restorePurchase)),
                                  onTap: () => IAPService.instance.restore(),
                                ),
                                ListTile(
                                  leading: const Icon(Icons.play_circle_outline,
                                      color: AppTheme.primary),
                                  title: Text(isFr
                                      ? 'Sans pub 60 min'
                                      : (isEs
                                          ? 'Sin anuncios 60 min'
                                          : 'Ad-free for 60 min')),
                                  subtitle: Text(isFr
                                      ? 'Regarder une pub pour débloquer'
                                      : (isEs
                                          ? 'Ver un anuncio para desbloquear'
                                          : 'Watch an ad to unlock')),
                                  onTap: () async {
                                    final earned =
                                        await adService.showRewarded();
                                    if (earned)
                                      freemiumService.activateRewarded();
                                    if (!earned && context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(isFr
                                              ? 'Pub non disponible'
                                              : (isEs
                                                  ? 'Anuncio no disponible'
                                                  : 'Ad not available')),
                                        ),
                                      );
                                    }
                                  },
                                ),
                                if (kDebugMode)
                                  ListTile(
                                    leading: const Icon(Icons.bug_report,
                                        color: CalcwiseSemanticColors.warnIcon),
                                    title: const Text('Force Premium (DEV)'),
                                    onTap: () =>
                                        freemiumService.debugUnlockPremium(),
                                  ),
                              ]);
                        },
                      ),
                      const Divider(height: 1),

                      // Language
                      _SectionHeader(headerLabel),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(children: [
                          Expanded(
                            child: _LangButton(
                              label: 'English',
                              selected: !isEs && !isFr,
                              onTap: () => _setLanguage('en'),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: _LangButton(
                              label: 'Español',
                              selected: isEs,
                              onTap: () => _setLanguage('es'),
                            ),
                          ),
                        ]),
                      ),
                      // Theme toggle
                      ValueListenableBuilder<ThemeMode>(
                        valueListenable: themeModeService.notifier,
                        builder: (_, mode, __) => ListTile(
                          leading: Icon(themeModeService.icon,
                              color: AppTheme.primary),
                          title: Text(themeModeService.label(isSpanish: isEs)),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppTheme.labelGray),
                          onTap: () => themeModeService.toggle(),
                        ),
                      ),
                      const Divider(height: 1),

                      // Support
                      _SectionHeader(
                          isFr ? 'SUPPORT' : (isEs ? 'SOPORTE' : 'SUPPORT')),
                      _SettingsTile(
                        icon: Icons.privacy_tip_rounded,
                        label: isFr
                            ? AppStringsFR.privacyPolicy
                            : (isEs
                                ? AppStringsES.privacyPolicy
                                : AppStringsEN.privacyPolicy),
                        onTap: () => _launch('https://calqwise.com/privacy'),
                      ),
                      _SettingsTile(
                        icon: Icons.manage_search_rounded,
                        label: isFr
                            ? 'Paramètres de confidentialité'
                            : (isEs
                                ? 'Configuración de privacidad'
                                : 'Privacy Settings'),
                        onTap: showCalcwisePrivacyOptions,
                      ),
                      CalcwiseRateAppTile(
                          label: isFr
                              ? "Noter l'app"
                              : (isEs ? 'Calificar la app' : 'Rate the App')),
                      _SettingsTile(
                        icon: Icons.email_rounded,
                        label: isFr
                            ? AppStringsFR.contactSupport
                            : (isEs
                                ? AppStringsES.contactSupport
                                : AppStringsEN.contactSupport),
                        onTap: () => _launch('mailto:support@calqwise.com'),
                      ),
                      const Divider(height: 1),

                      // Discover
                      _SectionHeader(isFr
                          ? AppStringsFR.discover.toUpperCase()
                          : (isEs
                              ? AppStringsES.discover.toUpperCase()
                              : AppStringsEN.discover.toUpperCase())),
                      _SettingsTile(
                        icon: Icons.apps_rounded,
                        label: 'CalqWise',
                        subtitle: isFr
                            ? AppStringsFR.calqwise
                            : (isEs
                                ? AppStringsES.calqwise
                                : AppStringsEN.calqwise),
                        onTap: () => _launch('https://calqwise.com'),
                      ),
                      _SettingsTile(
                        icon: Icons.grid_view_rounded,
                        label: isFr
                            ? 'Plus d\'apps CalqWise'
                            : (isEs
                                ? 'Más apps de CalqWise'
                                : 'More apps by CalqWise'),
                        subtitle: isFr
                            ? 'Voir toutes nos calculatrices'
                            : (isEs
                                ? 'Ver todas nuestras calculadoras'
                                : 'See all our calculators'),
                        onTap: () => _launch(
                            'https://play.google.com/store/apps/developer?id=CalqWise'),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.lg,
                            AppSpacing.sm, AppSpacing.lg, AppSpacing.lg),
                        child: Text(
                          isFr
                              ? AppStringsFR.disclaimer
                              : (isEs
                                  ? AppStringsES.disclaimer
                                  : AppStringsEN.disclaimer),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: CalcwiseTheme.of(context).textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
                const CalcwiseAdFooter(),
              ],
            );
          },
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
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, 6),
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
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.mdPlus),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.mdPlus),
          child: AnimatedContainer(
            duration: AppDuration.fast,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: selected ? AppTheme.primary : Colors.transparent,
              border: Border.all(
                  color: selected ? AppTheme.primary : Theme.of(context).colorScheme.outline),
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
