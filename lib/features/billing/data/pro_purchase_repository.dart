import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SubscriptionEntitlement {
  final bool storeActive;
  final String status;
  final String? productId;
  final String? provider;
  final DateTime? expiresAt;
  final bool willRenew;
  final String userId;

  const SubscriptionEntitlement({
    required this.storeActive,
    required this.status,
    required this.productId,
    required this.provider,
    required this.expiresAt,
    required this.willRenew,
    required this.userId,
  });

  factory SubscriptionEntitlement.fromMap(Map<Object?, Object?> value) {
    DateTime? expiresAt;
    final rawExpiry = value['expiresAt'];
    if (rawExpiry is String) {
      expiresAt = DateTime.tryParse(rawExpiry)?.toUtc();
    } else if (rawExpiry is num) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(
        rawExpiry.toInt(),
        isUtc: true,
      );
    }

    return SubscriptionEntitlement(
      storeActive: value['active'] == true,
      status: value['status'] as String? ?? 'inactive',
      productId: value['productId'] as String?,
      provider: value['provider'] as String?,
      expiresAt: expiresAt,
      willRenew: value['willRenew'] == true,
      userId: value['userId'] as String? ?? '',
    );
  }

  bool isActiveAt(DateTime now) {
    if (!storeActive) return false;
    final expiry = expiresAt;
    return expiry != null && expiry.isAfter(now.toUtc());
  }
}

class ProPurchaseRepository {
  static const keyLegacyStoreEntitlement = 'pro_store_entitlement';
  static const keyLegacyActiveProductId = 'pro_active_product_id';
  static const keyDebugIsPro = 'debug_is_pro_user';

  final SharedPreferences prefs;
  final FirebaseAuth auth;
  final FirebaseFunctions functions;

  const ProPurchaseRepository(
    this.prefs, {
    required this.auth,
    required this.functions,
  });

  static Future<ProPurchaseRepository> create() async {
    return ProPurchaseRepository(
      await SharedPreferences.getInstance(),
      auth: FirebaseAuth.instance,
      functions: FirebaseFunctions.instance,
    );
  }

  bool get debugIsPro => prefs.getBool(keyDebugIsPro) ?? false;

  Future<void> saveDebugOverride(bool isPro) {
    return prefs.setBool(keyDebugIsPro, isPro);
  }

  /// Removes the old, unverified, permanent entitlement. It must never be
  /// consulted when deciding whether paid features are available.
  Future<void> removeLegacyEntitlement() async {
    await prefs.remove(keyLegacyStoreEntitlement);
    await prefs.remove(keyLegacyActiveProductId);
  }

  Future<SubscriptionEntitlement> refreshEntitlement() async {
    _requireUser();
    final result = await functions
        .httpsCallable('getSubscriptionEntitlement')
        .call<Object?>();
    return _entitlementFromResult(result.data);
  }

  Future<SubscriptionEntitlement> verifyPurchase({
    required String productId,
    required String source,
    required String verificationData,
    String? purchaseId,
  }) async {
    _requireUser();
    final result = await functions
        .httpsCallable('verifySubscriptionPurchase')
        .call<Object?>({
      'productId': productId,
      'source': source,
      'verificationData': verificationData,
      if (purchaseId != null) 'purchaseId': purchaseId,
    });
    return _entitlementFromResult(result.data);
  }

  User _requireUser() {
    final user = auth.currentUser;
    if (user == null) {
      throw StateError(
        'Sign in before purchasing so Pro can follow your account.',
      );
    }
    return user;
  }

  SubscriptionEntitlement _entitlementFromResult(Object? data) {
    if (data is! Map) {
      throw StateError('The subscription service returned an invalid result.');
    }
    return SubscriptionEntitlement.fromMap(data);
  }
}
