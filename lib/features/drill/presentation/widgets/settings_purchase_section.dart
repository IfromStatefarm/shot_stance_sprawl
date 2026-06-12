import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_theme.dart';
import '../../providers.dart';

class SettingsProCalloutGate extends ConsumerWidget {
  final String currentLang;

  const SettingsProCalloutGate({
    super.key,
    required this.currentLang,
  });

  String _proSubtitle(ProPurchaseState purchaseState) {
    if (purchaseState.isPro) {
      return currentLang == 'es' ? 'Activo' : 'Active';
    }
    if (purchaseState.loading) {
      return currentLang == 'es'
          ? 'Cargando opciones de compra'
          : 'Loading purchase options';
    }
    if (purchaseState.errorMessage != null) {
      return purchaseState.errorMessage!;
    }
    final product = purchaseState.primaryProduct;
    if (product == null) {
      return currentLang == 'es'
          ? 'Coach Mode no disponible'
          : 'Coach Mode is unavailable';
    }
    return currentLang == 'es'
        ? 'Videos largos, voz de coach, ad libs y videos sin marca por ${product.price}'
        : 'Long review videos, coach voice, ad libs, and watermark-free saves for ${product.price}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proPurchase = ref.watch(proPurchaseProvider);
    final proProduct = proPurchase.primaryProduct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          leading: const Icon(Icons.lock, color: AppBrandColors.gold),
          title: const Text('Snap & Go Coach Mode'),
          subtitle: Text(currentLang == 'es'
              ? 'Agrega voz de coach, videos largos y ad libs'
              : 'Subscribe to add coach voice and long review videos'),
          trailing: FilledButton(
            onPressed: proPurchase.canBuy
                ? () => unawaited(
                      ref.read(proPurchaseProvider.notifier).buyPro(),
                    )
                : null,
            child: Text(
              proPurchase.purchasePending
                  ? '...'
                  : (proProduct?.price ?? 'COACH MODE'),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(72, 0, 16, 8),
          child: Text(
            _proSubtitle(proPurchase),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class SettingsRestorePurchasesTile extends ConsumerWidget {
  final String currentLang;

  const SettingsRestorePurchasesTile({
    super.key,
    required this.currentLang,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proPurchase = ref.watch(proPurchaseProvider);

    return ListTile(
      leading: const Icon(Icons.restore),
      title: Text(
        currentLang == 'es' ? 'Restaurar compras' : 'Restore Purchases',
      ),
      subtitle: Text(
        currentLang == 'es'
            ? 'Recupera Coach Mode en este dispositivo'
            : 'Recover Coach Mode on this device',
      ),
      trailing: proPurchase.restorePending
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.chevron_right),
      onTap: proPurchase.restorePending
          ? null
          : () => unawaited(
                ref.read(proPurchaseProvider.notifier).restorePurchases(),
              ),
    );
  }
}

class SettingsDebugSubscriptionTile extends ConsumerWidget {
  final String currentLang;

  const SettingsDebugSubscriptionTile({
    super.key,
    required this.currentLang,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPro = ref.watch(isProProvider);

    if (!kDebugMode) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        _SectionHeader(
          title: currentLang == 'es' ? 'Coach Mode' : 'Coach Mode',
        ),
        SwitchListTile(
          title: const Text('Simulate Coach Mode'),
          subtitle: const Text('Debug only: local entitlement override'),
          secondary: Icon(
            Icons.stars,
            color: isPro ? AppBrandColors.gold : Colors.grey,
          ),
          value: isPro,
          onChanged: (val) {
            ref.read(proPurchaseProvider.notifier).setDebugOverride(val);
          },
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppBrandColors.blue,
              letterSpacing: 1.2,
            ),
      ),
    );
  }
}
