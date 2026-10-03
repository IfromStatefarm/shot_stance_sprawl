import 'dart:async';
import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../core/firebase_bootstrap.dart';
import '../compliance/compliance.dart';
import 'data/pro_purchase_repository.dart';

const Set<String> proProductIds = {'snap_go_pro_monthly'};

const Object _unset = Object();

String storeAccountToken(String uid) {
  final bytes = sha256
      .convert(utf8.encode('snap-and-go-store-account:$uid'))
      .bytes
      .take(16)
      .toList();
  bytes[6] = (bytes[6] & 0x0f) | 0x50;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0'));
  final compact = hex.join();
  return '${compact.substring(0, 8)}-'
      '${compact.substring(8, 12)}-'
      '${compact.substring(12, 16)}-'
      '${compact.substring(16, 20)}-'
      '${compact.substring(20)}';
}

@immutable
class ProPurchaseState {
  final bool isPro;
  final bool ageEligible;
  final bool storeAvailable;
  final bool loading;
  final bool purchasePending;
  final bool restorePending;
  final List<ProductDetails> products;
  final String? activeProductId;
  final DateTime? expiresAt;
  final bool willRenew;
  final String entitlementStatus;
  final String? errorMessage;

  const ProPurchaseState({
    this.isPro = false,
    this.ageEligible = false,
    this.storeAvailable = false,
    this.loading = true,
    this.purchasePending = false,
    this.restorePending = false,
    this.products = const [],
    this.activeProductId,
    this.expiresAt,
    this.willRenew = false,
    this.entitlementStatus = 'inactive',
    this.errorMessage,
  });

  ProductDetails? get primaryProduct {
    for (final product in products) {
      if (proProductIds.contains(product.id)) return product;
    }
    return null;
  }

  bool get canBuy =>
      ageEligible &&
      storeAvailable &&
      !loading &&
      !purchasePending &&
      primaryProduct != null;

  ProPurchaseState copyWith({
    bool? isPro,
    bool? ageEligible,
    bool? storeAvailable,
    bool? loading,
    bool? purchasePending,
    bool? restorePending,
    List<ProductDetails>? products,
    Object? activeProductId = _unset,
    Object? expiresAt = _unset,
    bool? willRenew,
    String? entitlementStatus,
    Object? errorMessage = _unset,
  }) {
    return ProPurchaseState(
      isPro: isPro ?? this.isPro,
      ageEligible: ageEligible ?? this.ageEligible,
      storeAvailable: storeAvailable ?? this.storeAvailable,
      loading: loading ?? this.loading,
      purchasePending: purchasePending ?? this.purchasePending,
      restorePending: restorePending ?? this.restorePending,
      products: products ?? this.products,
      activeProductId: identical(activeProductId, _unset)
          ? this.activeProductId
          : activeProductId as String?,
      expiresAt: identical(expiresAt, _unset)
          ? this.expiresAt
          : expiresAt as DateTime?,
      willRenew: willRenew ?? this.willRenew,
      entitlementStatus: entitlementStatus ?? this.entitlementStatus,
      errorMessage: identical(errorMessage, _unset)
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

class ProPurchaseController extends Notifier<ProPurchaseState> {
  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  StreamSubscription<User?>? _authSubscription;
  Timer? _expiryTimer;
  Timer? _periodicRefreshTimer;
  ProPurchaseRepository? _repository;
  String? _entitlementUid;

  @override
  ProPurchaseState build() {
    final ageEligible =
        ref.watch(ageEligibilityProvider).allowsConnectedFeatures;
    if (!ageEligible) {
      return const ProPurchaseState(
        ageEligible: false,
        loading: false,
        errorMessage: 'Purchases are available only to users age 13 or older.',
      );
    }
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
    ref.onDispose(() {
      _purchaseSubscription?.cancel();
      _authSubscription?.cancel();
      _expiryTimer?.cancel();
      _periodicRefreshTimer?.cancel();
    });
    unawaited(_initialize());
    return const ProPurchaseState(ageEligible: true);
  }

  Future<void> _initialize() async {
    try {
      if (FirebaseBootstrap.isAvailable) {
        _repository = await ProPurchaseRepository.create();
        await _repository!.removeLegacyEntitlement();
        _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
          if (user?.uid == _entitlementUid) return;
          _clearEntitlement();
          if (user != null) unawaited(_refreshEntitlement(showErrors: false));
        });
        await _refreshEntitlement(showErrors: false);
        _periodicRefreshTimer = Timer.periodic(
          const Duration(minutes: 15),
          (_) => unawaited(_refreshEntitlement(showErrors: false)),
        );
      }
    } catch (error) {
      debugPrint('Subscription entitlement initialization failed: $error');
    }

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
    } catch (error) {
      state = state.copyWith(
        loading: false,
        errorMessage: 'Could not load store products: $error',
      );
    }
  }

  Future<void> buyPro() async {
    if (!state.ageEligible) {
      state = state.copyWith(
        errorMessage: 'Purchases are available only to users age 13 or older.',
      );
      return;
    }
    final product = state.primaryProduct;
    if (product == null) {
      state = state.copyWith(
        errorMessage:
            'Snap & Go Coach Mode is not available. Confirm snap_go_pro_monthly exists in both stores.',
      );
      return;
    }
    final user = FirebaseBootstrap.isAvailable
        ? FirebaseAuth.instance.currentUser
        : null;
    if (user == null) {
      state = state.copyWith(
        errorMessage: 'Sign in before subscribing so Pro follows your account.',
      );
      return;
    }

    try {
      state = state.copyWith(purchasePending: true, errorMessage: null);
      // Flutter's cross-store API represents auto-renewing subscriptions as
      // non-consumables. Product configuration determines that it renews.
      final purchaseParam = PurchaseParam(
        productDetails: product,
        // A one-way, deterministic UUID lets both stores attach this purchase
        // to the app account without disclosing the Firebase UID.
        applicationUserName: storeAccountToken(user.uid),
      );
      await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (error) {
      state = state.copyWith(
        purchasePending: false,
        errorMessage: 'Could not start purchase: $error',
      );
    }
  }

  Future<void> restorePurchases() async {
    if (!state.ageEligible) {
      state = state.copyWith(
        errorMessage: 'Purchases are available only to users age 13 or older.',
      );
      return;
    }
    if (!FirebaseBootstrap.isAvailable ||
        FirebaseAuth.instance.currentUser == null) {
      state = state.copyWith(
        errorMessage: 'Sign in before restoring purchases.',
      );
      return;
    }
    try {
      state = state.copyWith(restorePending: true, errorMessage: null);
      await _iap.restorePurchases();
      await _refreshEntitlement(showErrors: false);
      state = state.copyWith(restorePending: false);
    } catch (error) {
      state = state.copyWith(
        restorePending: false,
        errorMessage: 'Could not restore purchases: $error',
      );
    }
  }

  Future<void> setDebugOverride(bool isPro) async {
    if (!kDebugMode) return;
    final repository = _repository ?? await ProPurchaseRepository.create();
    _repository = repository;
    await repository.saveDebugOverride(isPro);
    if (isPro) {
      state = state.copyWith(isPro: true, entitlementStatus: 'debug');
    } else {
      await _refreshEntitlement(showErrors: false);
    }
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
      } else if (purchase.status == PurchaseStatus.canceled) {
        state = state.copyWith(
          purchasePending: false,
          restorePending: false,
          errorMessage: null,
        );
      } else if ((purchase.status == PurchaseStatus.purchased ||
              purchase.status == PurchaseStatus.restored) &&
          proProductIds.contains(purchase.productID)) {
        try {
          final repository =
              _repository ?? await ProPurchaseRepository.create();
          _repository = repository;
          final entitlement = await repository.verifyPurchase(
            productId: purchase.productID,
            source: purchase.verificationData.source,
            verificationData: purchase.verificationData.serverVerificationData,
            purchaseId: purchase.purchaseID,
          );
          _applyEntitlement(entitlement);
          if (!entitlement.isActiveAt(DateTime.now())) {
            state = state.copyWith(
              errorMessage: 'This subscription is no longer active.',
            );
          }
        } catch (error) {
          state = state.copyWith(errorMessage: _verificationError(error));
        }
      }

      if (purchase.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(purchase);
        } catch (error) {
          state = state.copyWith(
            errorMessage: 'Could not finish the store transaction: $error',
          );
        }
      }
    }

    state = state.copyWith(purchasePending: false, restorePending: false);
  }

  Future<void> _refreshEntitlement({required bool showErrors}) async {
    final repository = _repository;
    final user = FirebaseBootstrap.isAvailable
        ? FirebaseAuth.instance.currentUser
        : null;
    if (repository == null || user == null) {
      _clearEntitlement();
      return;
    }
    final requestedUid = user.uid;
    try {
      final entitlement = await repository.refreshEntitlement();
      if (FirebaseAuth.instance.currentUser?.uid != requestedUid) return;
      _applyEntitlement(entitlement);
    } catch (error) {
      if (showErrors) {
        state = state.copyWith(errorMessage: _verificationError(error));
      }
      // Never extend an expired entitlement when the server is unreachable.
      final expiry = state.expiresAt;
      if (expiry == null || !expiry.isAfter(DateTime.now().toUtc())) {
        _clearEntitlement();
      }
    }
  }

  void _applyEntitlement(SubscriptionEntitlement entitlement) {
    final debugOverride = kDebugMode && (_repository?.debugIsPro ?? false);
    final isActive = entitlement.isActiveAt(DateTime.now());
    _entitlementUid = entitlement.userId;
    _expiryTimer?.cancel();
    final expiry = entitlement.expiresAt;
    if (isActive && expiry != null) {
      _expiryTimer = Timer(expiry.difference(DateTime.now().toUtc()), () {
        _clearEntitlement();
        unawaited(_refreshEntitlement(showErrors: false));
      });
    }
    state = state.copyWith(
      isPro: isActive || debugOverride,
      activeProductId: isActive ? entitlement.productId : null,
      expiresAt: isActive ? entitlement.expiresAt : null,
      willRenew: isActive && entitlement.willRenew,
      entitlementStatus:
          debugOverride && !isActive ? 'debug' : entitlement.status,
      errorMessage: null,
    );
  }

  void _clearEntitlement() {
    _expiryTimer?.cancel();
    _entitlementUid = null;
    final debugOverride = kDebugMode && (_repository?.debugIsPro ?? false);
    state = state.copyWith(
      isPro: debugOverride,
      activeProductId: null,
      expiresAt: null,
      willRenew: false,
      entitlementStatus: debugOverride ? 'debug' : 'inactive',
    );
  }

  String _verificationError(Object error) {
    if (error is FirebaseFunctionsException) {
      return error.message ?? 'Purchase could not be verified.';
    }
    return 'Purchase could not be verified. Please try again.';
  }
}
