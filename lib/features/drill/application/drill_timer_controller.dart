import 'dart:async';

class DrillTimerController {
  final Stopwatch _stopwatch;

  Timer? _ticker;
  Timer? _nextTimer;
  Timer? _holdTimer;
  Timer? _adLibTimer;

  DrillTimerController({Stopwatch? stopwatch})
      : _stopwatch = stopwatch ?? Stopwatch();

  Duration get elapsed => _stopwatch.elapsed;

  void resetAndStart() {
    _stopwatch
      ..reset()
      ..start();
  }

  void start() => _stopwatch.start();

  void stop() => _stopwatch.stop();

  void startTicker({
    required int session,
    required int Function() currentSession,
    required bool Function() isFinishing,
    required Duration total,
    required void Function(Duration elapsed) onTick,
    required void Function() onComplete,
  }) {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (session != currentSession() || isFinishing()) {
        timer.cancel();
        return;
      }

      final elapsed = _stopwatch.elapsed;
      final cappedElapsed = elapsed >= total ? total : elapsed;
      onTick(cappedElapsed);

      if (cappedElapsed >= total) {
        timer.cancel();
        onComplete();
      }
    });
  }

  void scheduleNext(Duration delay, void Function() callback) {
    _nextTimer?.cancel();
    _nextTimer = Timer(delay, callback);
  }

  void scheduleHold(Duration hold, void Function() callback) {
    _holdTimer?.cancel();
    _holdTimer = Timer(hold, callback);
  }

  void scheduleAdLib(Duration delay, void Function() callback) {
    _adLibTimer?.cancel();
    _adLibTimer = Timer(delay, callback);
  }

  void cancelAdLib() {
    _adLibTimer?.cancel();
    _adLibTimer = null;
  }

  void cancel({bool keepTicker = false}) {
    _nextTimer?.cancel();
    _nextTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _adLibTimer?.cancel();
    _adLibTimer = null;
    if (!keepTicker) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void dispose() {
    cancel();
    _stopwatch.stop();
  }
}
