import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Set<String> proProductIds = {'snap_go_pro_monthly'};

const Object _unset = Object();

@immutable
class ProPurchaseState {
  final bool isPro;
  final bool storeAvailable;
  final bool loading;
  final bool purchasePending;
  final bool restorePending;
  final List<ProductDetails> products;
  final String? activeProductId;
  final String? errorMessage;

  const ProPurchaseState({
    this.isPro = false,
    this.storeAvailable = false,
    this.loading = true,
    this.purchasePending = false,
    this.restorePending = false,
    this.products = const [],
    this.activeProductId,
    this.errorMessage,
  });

  ProductDetails? get primaryProduct {
    for (final product in products) {
      if (proProductIds.contains(product.id)) return product;
    }
    return null;
  }

  bool get canBuy =>
      storeAvailable && !loading && !purchasePending && primaryProduct != null;

  ProPurchaseState copyWith({
    bool? isPro,
    bool? storeAvailable,
    bool? loading,
    bool? purchasePending,
    bool? restorePending,
    List<ProductDetails>? products,
    Object? activeProductId = _unset,
    Object? errorMessage = _unset,
  }) {
    return ProPurchaseState(
      isPro: isPro ?? this.isPro,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      loading: loading ?? this.loading,
      purchasePending: purchasePending ?? this.purchasePending,
      restorePending: restorePending ?? this.restorePending,
      products: products ?? this.products,
      activeProductId: identical(activeProductId, _unset)
          ? this.activeProductId
          : activeProductId as String?,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class ProPurchaseController extends Notifier<ProPurchaseState> {
  static const _keyStoreEntitlement = 'pro_store_entitlement';
  static const _keyActiveProductId = 'pro_active_product_id';
  static const _keyDebugIsPro = 'debug_is_pro_user';

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;

  @override
  ProPurchaseState build() {
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (Object error) {
        state = state.copyWith(
          purchasePending: false,
          restorePending: false,
          errorMessage: 'Purchase update failed: $error',
        );
      },
    );
    ref.onDispose(() => _purchaseSubscription?.cancel());
    unawaited(_initialize());
    return const ProPurchaseState();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final storedEntitlement = prefs.getBool(_keyStoreEntitlement) ?? false;
    final debugEntitlement =
        kDebugMode ? (prefs.getBool(_keyDebugIsPro) ?? false) : false;

    state = state.copyWith(
      isPro: storedEntitlement || debugEntitlement,
      activeProductId: prefs.getString(_keyActiveProductId),
    );

    try {
      final available = await _iap.isAvailable();
      if (!available) {
        state = state.copyWith(
          storeAvailable: false,
          loading: false,
          errorMessage: 'Store purchases are unavailable on this device.',
        );
        return;
      }

      final response = await _iap.queryProductDetails(proProductIds);
      final missingProduct = response.notFoundIDs.isNotEmpty
          ? 'Missing store product: ${response.notFoundIDs.join(', ')}'
          : null;

      state = state.copyWith(
        storeAvailable: true,
        loading: false,
        products: response.productDetails,
        errorMessage: response.error?.message ?? missingProduct,
      );
    } catch (e) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load store products: $e',
      );
    }
  }

  Future<void> buyPro() async {
    final product = state.primaryProduct;
    if (product == null) {
      state = state.copyWith(
        errorMessage:
            'Snap & Go Coach Mode is not available. Confirm snap_go_pro_monthly exists in both stores.',
      );
      return;
    }

    try {
      state = state.copyWith(purchasePending: true, errorMessage: null);
      final purchaseParam = PurchaseParam(productDetails: product);
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      state = state.copyWith(
        purchasePending: false,
        errorMessage: 'Could not start purchase: $e',
      );
    }
  }

  Future<void> restorePurchases() async {
    try {
      state = state.copyWith(restorePending: true, errorMessage: null);
      await _iap.restorePurchases();
    } catch (e) {
      state = state.copyWith(
        restorePending: false,
        errorMessage: 'Could not restore purchases: $e',
      );
    }
  }

  Future<void> setDebugOverride(bool isPro) async {
    if (!kDebugMode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyDebugIsPro, isPro);
    final storedEntitlement = prefs.getBool(_keyStoreEntitlement) ?? false;
    state = state.copyWith(isPro: storedEntitlement || isPro);
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.pending) {
        state = state.copyWith(purchasePending: true);
        continue;
      }

      if (purchase.status == PurchaseStatus.error) {
        state = state.copyWith(
          purchasePending: false,
          restorePending: false,
          errorMessage: purchase.error?.message ?? 'Purchase failed.',
        );
      }

      if (purchase.status == PurchaseStatus.canceled) {
        state = state.copyWith(
          purchasePending: false,
          restorePending: false,
          errorMessage: null,
        );
      }

      if ((purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) &&
          proProductIds.contains(purchase.productID)) {
        if (await _verifyPurchase(purchase)) {
          await _deliverProEntitlement(purchase.productID);
        } else {
          state = state.copyWith(
            purchasePending: false,
            restorePending: false,
            errorMessage: 'Purchase could not be verified.',
          );
        }
      }

      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }

    state = state.copyWith(purchasePending: false, restorePending: false);
  }

  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    return proProductIds.contains(purchase.productID) &&
        purchase.verificationData.serverVerificationData.isNotEmpty;
  }

  Future<void> _deliverProEntitlement(String productId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyStoreEntitlement, true);
    await prefs.setString(_keyActiveProductId, productId);

    state = state.copyWith(
      isPro: true,
      activeProductId: productId,
      errorMessage: null,
    );
  }
}
