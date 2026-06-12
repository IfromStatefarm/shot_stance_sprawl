import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app_theme.dart';
import '../../providers.dart';

const Map<String, String> _calloutIconAssets = {
  'add_new': 'assets/images/callout_icons/add_new_icon_button.png',
  'circle': 'assets/images/callout_icons/circle_button_icon.png',
  'down_block': 'assets/images/callout_icons/down_block_button_icon.png',
  'fake': 'assets/images/callout_icons/fake_button_icon.png',
  'foot_fire': 'assets/images/callout_icons/foot_fire_button_icon.png',
  'hand_fight': 'assets/images/callout_icons/hand_fight_button_icon.png',
  'high_knees': 'assets/images/callout_icons/high_knees_button_icon.png',
  'level_change': 'assets/images/callout_icons/level_change_button_icon.png',
  'shot': 'assets/images/callout_icons/shot_button_icon.png',
  'snap_down': 'assets/images/callout_icons/snap_down_button_icon.png',
  'sprawl': 'assets/images/callout_icons/sprawl_button_icon.png',
  'stance': 'assets/images/callout_icons/stance_button_icon.png',
};

const _addNewIconAsset = 'assets/images/callout_icons/add_new_icon_button.png';

class AddNewCalloutTile extends ConsumerWidget {
  final VoidCallback onTap;
  final bool compact;

  const AddNewCalloutTile({
    super.key,
    required this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(languageProvider);
    final isEs = lang == 'es';
    final radius = BorderRadius.circular(compact ? 10 : 16);

    return Semantics(
      button: true,
      label: isEs ? 'Agregar nuevo comando' : 'Add new callout',
      child: Card(
        margin: compact ? EdgeInsets.zero : null,
        clipBehavior: Clip.antiAlias,
        elevation: 5,
        color: AppBrandColors.black,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: AppBrandColors.gold.withValues(alpha: 0.95),
            width: 2,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  _addNewIconAsset,
                  fit: BoxFit.cover,
                  semanticLabel: isEs ? 'Agregar nuevo' : 'Add new',
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.18),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  width: compact ? 28 : 34,
                  height: compact ? 28 : 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppBrandColors.gold,
                    border: Border.all(color: Colors.white, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.28),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.add,
                    color: AppBrandColors.black,
                    size: compact ? 20 : 24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeCalloutTile extends ConsumerWidget {
  final Callout callout;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final VoidCallback onRecordTapped;
  final bool compact;

  const HomeCalloutTile({
    super.key,
    required this.callout,
    required this.enabled,
    required this.onChanged,
    required this.onRecordTapped,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(drillConfigProvider);
    final savedAudioPath =
        config.customAudioPaths[callout.id] ?? callout.audioUrl;
    final hasRecording = savedAudioPath != null && savedAudioPath.isNotEmpty;
    final overrideMap = config.calloutOverrideDurations;
    final currentDuration =
        overrideMap[callout.id] ?? callout.defaultDurationSeconds;

    final isPro = ref.watch(isProProvider);
    final proPurchase = ref.watch(proPurchaseProvider);
    final lang = ref.watch(languageProvider);
    final buttonStyle = ref.watch(calloutButtonStyleProvider);
    final displayName = lang == 'es' ? callout.nameEs : callout.nameEn;
    final iconAsset = buttonStyle == CalloutButtonStyle.modern
        ? _calloutIconAssets[callout.id]
        : null;

    final radius = BorderRadius.circular(compact ? 10 : 16);

    return AnimatedScale(
      scale: enabled ? 1.02 : 0.96,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      child: Card(
        margin: compact ? EdgeInsets.zero : null,
        clipBehavior: Clip.antiAlias,
        elevation: enabled ? (compact ? 2 : 3) : 1,
        color: enabled
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.3)
            : Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: enabled
              ? BorderSide(color: AppBrandColors.red, width: compact ? 1.5 : 2)
              : BorderSide.none,
        ),
        child: InkWell(
          onTap: () => onChanged(!enabled),
          borderRadius: radius,
          child: Stack(
            children: [
              Positioned.fill(
                child: iconAsset == null
                    ? _TextCalloutButtonContent(
                        displayName: displayName,
                        enabled: enabled,
                      )
                    : _IconCalloutButtonContent(
                        assetPath: iconAsset,
                        enabled: enabled,
                        semanticLabel: displayName,
                      ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () {
                    if (isPro) {
                      onRecordTapped();
                    } else if (proPurchase.canBuy) {
                      unawaited(
                          ref.read(proPurchaseProvider.notifier).buyPro());
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            proPurchase.errorMessage ??
                                'Snap & Go Coach Mode is loading. Try again in a moment.',
                          ),
                        ),
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconAsset == null
                          ? Theme.of(context).canvasColor.withValues(alpha: 0.5)
                          : Colors.black.withValues(alpha: 0.45),
                    ),
                    child: Icon(
                      !isPro && !callout.isCustom
                          ? Icons.lock
                          : (hasRecording ? Icons.mic : Icons.mic_none),
                      size: compact ? 14 : 16,
                      color: !isPro
                          ? AppBrandColors.gold
                          : (hasRecording ? AppBrandColors.blue : Colors.grey),
                    ),
                  ),
                ),
              ),
              if (callout.type == 'Duration')
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () {
                      if (!enabled) return;
                      _showDurationPicker(
                        context,
                        ref,
                        callout.id,
                        currentDuration,
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: enabled
                            ? AppBrandColors.gold
                            : AppBrandColors.gold.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${currentDuration}s',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppBrandColors.black,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showDurationPicker(
    BuildContext context,
    WidgetRef ref,
    String id,
    int current,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20),
          height: 200,
          child: Column(
            children: [
              const Text(
                'Select Duration',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [5, 15, 30, 45, 60].map((val) {
                  final isSelected = val == current;
                  return ChoiceChip(
                    label: Text('${val}s'),
                    selected: isSelected,
                    onSelected: (_) {
                      ref
                          .read(drillConfigProvider.notifier)
                          .setCalloutDuration(id, val);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _IconCalloutButtonContent extends StatelessWidget {
  static const _grayscaleFilter = ColorFilter.matrix(<double>[
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0.2126,
    0.7152,
    0.0722,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ]);

  final String assetPath;
  final bool enabled;
  final String semanticLabel;

  const _IconCalloutButtonContent({
    required this.assetPath,
    required this.enabled,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      assetPath,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      semanticLabel: semanticLabel,
    );

    if (enabled) return image;

    return Opacity(
      opacity: 0.48,
      child: ColorFiltered(
        colorFilter: _grayscaleFilter,
        child: image,
      ),
    );
  }
}

class _TextCalloutButtonContent extends StatelessWidget {
  final String displayName;
  final bool enabled;

  const _TextCalloutButtonContent({
    required this.displayName,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: enabled
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            enabled ? 'ON' : 'OFF',
            style: TextStyle(
              fontSize: 10,
              color: enabled ? AppBrandColors.red : Colors.grey,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
