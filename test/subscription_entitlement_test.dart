import 'package:flutter_test/flutter_test.dart';
import 'package:shot_stance_sprawl/features/billing/pro_purchase.dart';
import 'package:shot_stance_sprawl/features/billing/data/pro_purchase_repository.dart';

void main() {
  test('store account tokens are stable UUIDs and do not expose the uid', () {
    final token = storeAccountToken('firebase-user-123');

    expect(token, 'f3a771a1-e34f-5c7e-b4c6-a49b28bb92ad');
    expect(token, matches(RegExp(r'^[a-f0-9-]{36}$')));
    expect(token, storeAccountToken('firebase-user-123'));
    expect(token, isNot(contains('firebase-user-123')));
    expect(token, isNot(storeAccountToken('another-user')));
  });

  group('SubscriptionEntitlement', () {
    test('accepts a server-active entitlement before its expiry', () {
      final now = DateTime.utc(2026, 9, 24);
      final entitlement = SubscriptionEntitlement.fromMap({
        'active': true,
        'status': 'active',
        'productId': 'snap_go_pro_monthly',
        'provider': 'app_store',
        'expiresAt': now.add(const Duration(days: 1)).toIso8601String(),
        'willRenew': true,
        'userId': 'account-a',
      });

      expect(entitlement.isActiveAt(now), isTrue);
      expect(entitlement.willRenew, isTrue);
      expect(entitlement.userId, 'account-a');
    });

    test('rejects an expired entitlement even if active is stale', () {
      final now = DateTime.utc(2026, 9, 24);
      final entitlement = SubscriptionEntitlement.fromMap({
        'active': true,
        'status': 'active',
        'expiresAt': now.subtract(const Duration(seconds: 1)).toIso8601String(),
        'userId': 'account-a',
      });

      expect(entitlement.isActiveAt(now), isFalse);
    });

    test('rejects revoked access before the recorded expiry', () {
      final now = DateTime.utc(2026, 9, 24);
      final entitlement = SubscriptionEntitlement.fromMap({
        'active': false,
        'status': 'revoked',
        'expiresAt': now.add(const Duration(days: 20)).millisecondsSinceEpoch,
        'userId': 'account-a',
      });

      expect(entitlement.isActiveAt(now), isFalse);
      expect(entitlement.status, 'revoked');
    });

    test('fails closed when expiry is absent or malformed', () {
      expect(
        SubscriptionEntitlement.fromMap({
          'active': true,
          'expiresAt': 'not-a-date',
        }).isActiveAt(DateTime.utc(2026)),
        isFalse,
      );
    });
  });
}
