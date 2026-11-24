import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_platform_interface/in_app_purchase_platform_interface.dart'
    show InAppPurchasePlatform;

import 'supporter_billing.dart';

class GooglePlaySupporterStore implements SupporterStore {
  final _iap = InAppPurchase.instance;

  @override
  Stream<List<PurchaseDetails>> get updates => _iap.purchaseStream;

  @override
  Future<bool> isAvailable() => _iap.isAvailable();

  @override
  Future<ProductDetails?> product(String id) async {
    final response = await _iap.queryProductDetails({id});
    if (response.error case final error?) throw error;
    return response.productDetails
        .whereType<GooglePlayProductDetails>()
        .where(
          (product) =>
              product.id == id &&
              product.productDetails.productType == ProductType.inapp,
        )
        .firstOrNull;
  }

  @override
  Future<List<PurchaseDetails>> ownedPurchases() async {
    final response = await _iap
        .getPlatformAddition<InAppPurchaseAndroidPlatformAddition>()
        .queryPastPurchases();
    if (response.error case final error?) throw error;
    return response.pastPurchases;
  }

  @override
  Future<bool> buy(ProductDetails product) => _iap.buyNonConsumable(
      purchaseParam: PurchaseParam(productDetails: product));

  @override
  Future<void> acknowledge(PurchaseDetails purchase) async {
    // The cross-platform API returns void even when Play reports a failure.
    final android =
        InAppPurchasePlatform.instance as InAppPurchaseAndroidPlatform;
    final result = await android.completePurchase(purchase);
    if (result.responseCode != BillingResponse.ok) {
      throw StateError('Google Play acknowledgment failed');
    }
  }
}
