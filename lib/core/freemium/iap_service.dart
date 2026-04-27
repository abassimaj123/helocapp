import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'freemium_service.dart';
import '../firebase/analytics_service.dart';
import '../services/review_service.dart';

final iapErrorNotifier = ValueNotifier<String?>(null);

class IAPService {
  IAPService._();
  static final instance = IAPService._();

  static const productId = 'premium_upgrade';

  StreamSubscription<List<PurchaseDetails>>? _sub;

  Future<void> initialize() async {
    _sub = InAppPurchase.instance.purchaseStream.listen(_handlePurchases);
    try {
      await InAppPurchase.instance
          .restorePurchases()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      iapErrorNotifier.value = 'Restore timed out. Try again.';
    } catch (e) {
      debugPrint('IAP restore error: $e');
    }
  }

  Future<void> buy() async {
    final available = await InAppPurchase.instance.isAvailable();
    if (!available) {
      iapErrorNotifier.value = 'In-app purchases not available on this device.';
      return;
    }
    try {
      final response = await InAppPurchase.instance
          .queryProductDetails({productId}).timeout(const Duration(seconds: 10));
      if (response.productDetails.isEmpty) {
        iapErrorNotifier.value = 'Product not found. Check Play Console.';
        return;
      }
      final param =
          PurchaseParam(productDetails: response.productDetails.first);
      await InAppPurchase.instance.buyNonConsumable(purchaseParam: param);
    } on TimeoutException {
      iapErrorNotifier.value = 'Purchase timed out. Please try again.';
    } catch (e) {
      iapErrorNotifier.value = 'Purchase failed: $e';
    }
  }

  Future<void> restore() async {
    try {
      await InAppPurchase.instance
          .restorePurchases()
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      iapErrorNotifier.value = 'Restore timed out. Try again.';
    } catch (e) {
      debugPrint('IAP restore error: $e');
    }
  }

  void _handlePurchases(List<PurchaseDetails> purchases) {
    for (final p in purchases) {
      if (p.productID == productId) {
        if (p.status == PurchaseStatus.purchased) {
          freemiumService.activatePremium();
          AnalyticsService.instance.logPurchased();
          ReviewService.instance.requestReview();
          debugPrint('Premium purchased');
        } else if (p.status == PurchaseStatus.restored) {
          freemiumService.activatePremium();
          AnalyticsService.instance.logRestored();
          debugPrint('Premium restored');
        } else if (p.status == PurchaseStatus.error) {
          iapErrorNotifier.value = p.error?.message ?? 'Purchase failed.';
          debugPrint('IAP error: ${p.error}');
        }
        if (p.pendingCompletePurchase) {
          InAppPurchase.instance.completePurchase(p);
        }
      }
    }
  }

  void dispose() => _sub?.cancel();
}
