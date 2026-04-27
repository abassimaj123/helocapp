# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Crashlytics
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**

# AdMob
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Google Play Billing (IAP)
-keep class com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# Google Play Review
-keep class com.google.android.play.core.review.** { *; }
-dontwarn com.google.android.play.core.**

# SQLite / sqflite
-keep class io.flutter.plugins.sqflite.** { *; }

# Shared preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }
