import 'package:flutter/material.dart';

import '../../../../app_theme.dart';

class HomeVideoToggle extends StatelessWidget {
  final bool isEnabled;
  final bool isEs;
  final VoidCallback onTap;

  const HomeVideoToggle({
    super.key,
    required this.isEnabled,
    required this.isEs,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          isEs ? 'GRABAR VIDEO' : 'RECORD VIDEO',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 12),
        GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isEnabled ? Colors.red : Colors.grey[300],
              boxShadow: isEnabled
                  ? [
                      BoxShadow(
                        color: Colors.red.withValues(alpha: 0.5),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ]
                  : [],
            ),
            child: Icon(
              isEnabled ? Icons.videocam : Icons.videocam_off,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class HomeDifficultyControl extends StatelessWidget {
  final bool isEs;
  final String selectedLabel;
  final double value;
  final ValueChanged<double> onChanged;

  const HomeDifficultyControl({
    super.key,
    required this.isEs,
    required this.selectedLabel,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.speed, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              isEs ? 'Dificultad:' : 'Difficulty:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              selectedLabel,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppBrandColors.blue,
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: 0,
          max: 3,
          divisions: 3,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class HomeDurationControl extends StatelessWidget {
  final bool isEs;
  final double value;
  final int maxMinutes;
  final bool showFreeVideoDurationHint;
  final bool isLocked;
  final VoidCallback onLockedInteraction;
  final ValueChanged<double> onChanged;

  const HomeDurationControl({
    super.key,
    required this.isEs,
    required this.value,
    required this.maxMinutes,
    required this.showFreeVideoDurationHint,
    required this.isLocked,
    required this.onLockedInteraction,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            const Icon(Icons.timer, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            Text(
              isEs ? 'DuraciÃ³n:' : 'Duration:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              '${value.round()} min',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
        if (showFreeVideoDurationHint)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 28),
                Expanded(
                  child: Text(
                    'Coach Mode unlocks longer videos, or toggle recording for longer drills',
                    style: TextStyle(
                      color: AppBrandColors.goldDark,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Slider(
          value: value,
          min: 1,
          max: maxMinutes.toDouble(),
          divisions: maxMinutes - 1,
          label: '${value.round()} min',
          onChangeStart: (_) {
            if (isLocked) onLockedInteraction();
          },
          onChanged: (nextValue) {
            if (isLocked) {
              onLockedInteraction();
              return;
            }

            onChanged(nextValue);
          },
        ),
      ],
    );
  }
}
