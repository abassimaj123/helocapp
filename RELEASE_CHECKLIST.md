# HELOC Calculator — Release Checklist

**App:** HELOC Calculator — Home Equity  
**Price:** $2.99  
**Last updated:** April 30, 2026

---

## Pre-Build

- [ ] Replace all `XXXXXXXXXX` AdMob unit IDs in `lib/config/ad_config.dart` and `lib/core/ads/ad_config.dart` with real IDs from AdMob console
- [ ] Replace test AdMob App ID `ca-app-pub-3940256099942544~3347511713` in `AndroidManifest.xml` with production ID
- [ ] Verify `kReleaseMode` guards on all ad unit IDs
- [ ] Set correct `applicationId` in `android/app/build.gradle`
- [ ] Update `versionName` and `versionCode` in `android/app/build.gradle`
- [ ] Confirm Firebase `google-services.json` is production (not dev)
- [ ] Remove any `debugUnlockPremium()` calls in production paths
- [ ] Verify IAP product ID in `IAPService` matches Play Console product

## Build

- [ ] Run `flutter build appbundle --release`
- [ ] Confirm no analysis warnings: `flutter analyze`
- [ ] AAB generated successfully in `build/app/outputs/bundle/release/`

## Play Console — Store Listing

- [ ] Upload AAB
- [ ] en-US title, short description, full description from `store/en-US/listing.txt`
- [ ] es-US title, short description, full description from `store/es-US/listing.txt`
- [ ] Upload screenshots (phone + 7-inch tablet minimum)
- [ ] App icon (512x512 PNG, no alpha)
- [ ] Feature graphic (1024x500 PNG)
- [ ] Privacy policy URL pointing to hosted `store/privacy.html`

## Play Console — Release

- [ ] Set content rating (Finance)
- [ ] Confirm CCPA / data safety form filled (no data sold, limited analytics)
- [ ] Create internal track release, test on device
- [ ] Promote to production track
- [ ] Confirm $2.99 price set in all target countries

## Post-Release

- [ ] Verify ads serving in production (banner + interstitial)
- [ ] Verify IAP purchase flow end-to-end
- [ ] Verify ReviewService triggers after 3rd save (90-day cooldown)
- [ ] Monitor Crashlytics for day-1 issues
- [ ] Monitor Firebase Analytics for first-week retention
