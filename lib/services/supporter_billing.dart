import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

const supporterProductId = 'library_supporter_badge';

abstract interface class SupporterStore {
  Stream<List<PurchaseDetails>> get updates;
  Future<bool> isAvailable();
  Future<ProductDetails?> product(String id);
  Future<List<PurchaseDetails>> ownedPurchases();
  Future<bool> buy(ProductDetails product);
  Future<void> acknowledge(PurchaseDetails purchase);
}

enum SupporterStatus {
  initializing,
  storeUnavailable,
  productUnavailable,
  available,
  checkout,
  pending,
  verifying,
  owned,
  canceled,
  purchaseFailed,
  alreadyOwned,
  restoring,
  restored,
  noPurchase,
  verificationUnavailable,
  verificationRejected,
  restoreFailed,
}

class SupporterBilling extends ChangeNotifier {
  SupporterBilling(this._store) {
    _subscription = _store.updates.listen(
      (purchases) => unawaited(_enqueue(() => _onUpdates(purchases))),
      onError: (Object error) => unawaited(_enqueue(() async {
        _checkout = false;
        _setStatus(SupporterStatus.verificationUnavailable);
      })),
    );
  }

  final SupporterStore _store;
  late final StreamSubscription<List<PurchaseDetails>> _subscription;
  Future<void> _operations = Future.value();
  bool _disposed = false;
  bool _checkout = false;
  bool _refreshing = false;
  bool _ownershipKnown = false;
  String? _acknowledgedToken;

  ProductDetails? _product;
  ProductDetails? get product => _product;
  bool _owned = false;
  bool get owned => _owned;
  SupporterStatus _status = SupporterStatus.initializing;
  SupporterStatus get status => _status;

  bool get canBuy =>
      _product != null &&
      _ownershipKnown &&
      !_owned &&
      !_checkout &&
      !_refreshing &&
      switch (_status) {
        SupporterStatus.available ||
        SupporterStatus.noPurchase ||
        SupporterStatus.canceled ||
        SupporterStatus.purchaseFailed =>
          true,
        _ => false,
      };

  bool get canRestore => !_refreshing && _status != SupporterStatus.verifying;

  Future<void> refresh({bool manual = false}) {
    if (_disposed || _refreshing) return Future.value();
    _refreshing = true;
    if (manual) _status = SupporterStatus.restoring;
    notifyListeners();
    return _enqueue(() async {
      try {
        await _refresh(manual: manual);
      } finally {
        _refreshing = false;
        if (!_disposed) notifyListeners();
      }
    });
  }

  Future<void> _refresh({required bool manual}) async {
    _ownershipKnown = false;
    _product = null;
    try {
      if (!await _store.isAvailable()) {
        _setStatus(manual
            ? SupporterStatus.restoreFailed
            : SupporterStatus.storeUnavailable);
        return;
      }
    } catch (_) {
      _setStatus(manual
          ? SupporterStatus.restoreFailed
          : SupporterStatus.storeUnavailable);
      return;
    }
    final previousStatus = _status;
    await _reconcile(
      manual: manual,
      emptyStatus: switch (previousStatus) {
        SupporterStatus.canceled ||
        SupporterStatus.purchaseFailed =>
          previousStatus,
        _ => SupporterStatus.available,
      },
    );
    try {
      final product = await _store.product(supporterProductId);
      if (product?.id == supporterProductId) _product = product;
      if (_status == SupporterStatus.available && _product == null) {
        _setStatus(SupporterStatus.productUnavailable);
      }
    } catch (_) {
      if (_status == SupporterStatus.available) {
        _setStatus(SupporterStatus.storeUnavailable);
      }
    }
  }

  Future<void> buy() {
    if (_disposed || !canBuy) return Future.value();
    // Take the lock before yielding, including while checking current ownership.
    final product = _product!;
    _checkout = true;
    _setStatus(SupporterStatus.checkout);
    return _enqueue(() async {
      await _reconcile(emptyStatus: SupporterStatus.checkout);
      if (_disposed || _status != SupporterStatus.checkout || _owned) {
        _checkout = false;
        if (_owned) _setStatus(SupporterStatus.alreadyOwned);
        return;
      }
      try {
        if (await _store.buy(product)) return;
        _checkout = false;
        // The account may have acquired ownership since the preflight query.
        await _reconcile(emptyStatus: SupporterStatus.purchaseFailed);
        if (_owned) _setStatus(SupporterStatus.alreadyOwned);
      } catch (_) {
        _setStatus(SupporterStatus.purchaseFailed);
      }
      _checkout = false;
      if (!_disposed) notifyListeners();
    });
  }

  Future<void> _onUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      final status = purchase.status;
      final checkoutError = purchase.productID.isEmpty &&
          _checkout &&
          (status == PurchaseStatus.canceled || status == PurchaseStatus.error);
      if (purchase.productID != supporterProductId && !checkoutError) continue;
      final wasCheckingOut = _checkout;
      _checkout = false;
      switch (status) {
        case PurchaseStatus.pending:
          if (!_owned) _setStatus(SupporterStatus.pending);
        case PurchaseStatus.canceled:
          if (!_owned) _setStatus(SupporterStatus.canceled);
        case PurchaseStatus.error:
          if (_owned) continue;
          if (wasCheckingOut) {
            await _reconcile(emptyStatus: SupporterStatus.purchaseFailed);
            if (_owned) _setStatus(SupporterStatus.alreadyOwned);
          } else {
            _setStatus(SupporterStatus.purchaseFailed);
          }
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final token = _token(purchase);
          if (token.isEmpty || purchase.error != null) {
            _setStatus(SupporterStatus.verificationRejected);
            continue;
          }
          await _reconcile(expectedToken: token);
      }
    }
  }

  Future<void> _reconcile({
    bool manual = false,
    String? expectedToken,
    SupporterStatus emptyStatus = SupporterStatus.available,
  }) async {
    if (expectedToken != null && !_owned) {
      _setStatus(SupporterStatus.verifying);
    }
    try {
      final purchases = (await _store.ownedPurchases())
          .where((purchase) => purchase.productID == supporterProductId)
          .toList();
      if (_disposed) return;
      final confirmed = purchases.where((purchase) =>
          (purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) &&
          purchase.error == null &&
          _token(purchase).isNotEmpty);
      final purchase = confirmed
          .where((purchase) =>
              expectedToken == null || _token(purchase) == expectedToken)
          .firstOrNull;
      if (purchase == null) {
        _ownershipKnown = purchases.isEmpty;
        final completeSnapshot = purchases.every((purchase) =>
            purchase.status == PurchaseStatus.pending ||
            confirmed.contains(purchase));
        if (completeSnapshot &&
            !confirmed
                .any((purchase) => _token(purchase) == _acknowledgedToken)) {
          _owned = false;
          _acknowledgedToken = null;
        }
        if (purchases
            .any((purchase) => purchase.status == PurchaseStatus.pending)) {
          _checkout = false;
          _setStatus(SupporterStatus.pending);
        } else if (expectedToken != null || purchases.isNotEmpty) {
          _setStatus(SupporterStatus.verificationRejected);
        } else if (manual) {
          _checkout = false;
          _setStatus(SupporterStatus.noPurchase);
        } else {
          _setStatus(_checkout ? SupporterStatus.checkout : emptyStatus);
        }
        return;
      }

      _checkout = false;
      final token = _token(purchase);
      if (_acknowledgedToken != token) _owned = false;
      if (purchase.pendingCompletePurchase && _acknowledgedToken != token) {
        _setStatus(SupporterStatus.verifying);
        await _store.acknowledge(purchase);
      }
      if (_disposed) return;
      _acknowledgedToken = token;
      _owned = true;
      _ownershipKnown = true;
      _setStatus(manual ? SupporterStatus.restored : SupporterStatus.owned);
    } catch (_) {
      _ownershipKnown = false;
      _setStatus(manual
          ? SupporterStatus.restoreFailed
          : SupporterStatus.verificationUnavailable);
    }
  }

  String _token(PurchaseDetails purchase) =>
      purchase.verificationData.serverVerificationData.trim();

  void _setStatus(SupporterStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  Future<void> _enqueue(Future<void> Function() action) {
    _operations = _operations.then((_) async {
      if (!_disposed) await action();
    });
    return _operations;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
