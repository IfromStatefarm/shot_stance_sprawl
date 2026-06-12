import 'dart:async';

import '../models.dart';

class CountdownDrillStart {
  final DrillConfig config;
  final List<Callout> callouts;
  final bool isPro;

  const CountdownDrillStart({
    required this.config,
    required this.callouts,
    required this.isPro,
  });
}

class DrillCountdownController {
  final Duration tick;
  Timer? _timer;
  Future<CountdownDrillStart>? _preparation;
  int? _count;

  DrillCountdownController({
    this.tick = const Duration(seconds: 1),
  });

  void start({
    required Future<CountdownDrillStart> Function() prepare,
    required Future<void> Function(CountdownDrillStart prepared) startDrill,
    required bool Function() shouldAbort,
    required void Function(int? count) onCountChanged,
    required void Function(bool showGo) onShowGoChanged,
  }) {
    cancel();
    _count = 5;
    onCountChanged(_count);
    _preparation = prepare();

    _timer = Timer.periodic(tick, (timer) async {
      if (shouldAbort()) {
        timer.cancel();
        return;
      }

      final currentCount = _count;
      if (currentCount != null && currentCount > 1) {
        _count = currentCount - 1;
        onCountChanged(_count);
        return;
      }

      if (_count == 1) {
        timer.cancel();
        final prepared = await (_preparation ?? prepare());

        if (shouldAbort()) return;
        onShowGoChanged(true);

        await startDrill(prepared);

        if (shouldAbort()) return;
        _count = null;
        onCountChanged(null);

        Future.delayed(const Duration(milliseconds: 350), () {
          if (!shouldAbort()) onShowGoChanged(false);
        });
      }
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
    _preparation = null;
  }

  void dispose() => cancel();
}
