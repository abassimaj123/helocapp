# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.embedding.**

# Firebase / Crashlytics
-keep class com.google.firebase.** { *; }
-keep class com.google.firebase.analytics.** { *; }
-keep class com.google.firebase.crashlytics.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
# Crashlytics — readable stack traces in release builds
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keep public class * extends java.lang.Exception

# AdMob
-keep class com.google.android.gms.ads.** { *; }
-dontwarn com.google.android.gms.ads.**

# Google Play Billing (IAP)
-keep class com.android.billingclient.** { *; }
-keep interface com.android.billingclient.** { *; }
-dontwarn com.android.billingclient.**

# Google Play Review
-keep class com.google.android.play.core.review.** { *; }
-dontwarn com.google.android.play.core.**

# SQLite / sqflite
-keep class io.flutter.plugins.sqflite.** { *; }

# Shared preferences
-keep class io.flutter.plugins.sharedpreferences.** { *; }
