import 'dart:async';

enum DrillAudioPriority {
  adLib,
  callout,
  whistle,
}

class DrillAudioCancellation {
  final Completer<void> _cancelled = Completer<void>();

  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;

  void _cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

class DrillAudioCoordinator {
  final List<_QueuedAudioOperation> _pending = [];

  _QueuedAudioOperation? _active;
  var _nextSequence = 0;
  var _isDraining = false;

  Future<T?> run<T>({
    required DrillAudioPriority priority,
    required Future<T> Function(DrillAudioCancellation cancellation) operation,
    bool preemptLowerPriorities = true,
  }) {
    final queued = _QueuedAudioOperation(
      priority: priority,
      sequence: _nextSequence++,
      operation: (cancellation) => operation(cancellation),
    );

    if (preemptLowerPriorities) {
      final superseded = _pending
          .where((pending) => pending.priority.index < priority.index)
          .toList();
      for (final pending in superseded) {
        _pending.remove(pending);
        pending.cancelBeforeStart();
      }

      final active = _active;
      if (active != null && active.priority.index < priority.index) {
        active.cancelWhileActive();
      }
    }

    _pending
      ..add(queued)
      ..sort((a, b) {
        final byPriority = b.priority.index.compareTo(a.priority.index);
        return byPriority != 0 ? byPriority : a.sequence.compareTo(b.sequence);
      });
    _drain();

    return queued.result.then((value) => value as T?);
  }

  void cancelAll() {
    final pending = List<_QueuedAudioOperation>.from(_pending);
    _pending.clear();
    for (final operation in pending) {
      operation.cancelBeforeStart();
    }
    _active?.cancelWhileActive();
  }

  void _drain() {
    if (_isDraining) return;
    _isDraining = true;

    unawaited(() async {
      while (_pending.isNotEmpty) {
        final operation = _pending.removeAt(0);
        _active = operation;
        await operation.execute();
        if (identical(_active, operation)) _active = null;
      }
      _isDraining = false;
    }());
  }
}

class _QueuedAudioOperation {
  final DrillAudioPriority priority;
  final int sequence;
  final Future<Object?> Function(DrillAudioCancellation cancellation) operation;
  final DrillAudioCancellation cancellation = DrillAudioCancellation();
  final Completer<Object?> _result = Completer<Object?>();

  _QueuedAudioOperation({
    required this.priority,
    required this.sequence,
    required this.operation,
  });

  Future<Object?> get result => _result.future;

  Future<void> execute() async {
    if (cancellation.isCancelled) {
      if (!_result.isCompleted) _result.complete(null);
      return;
    }

    try {
      final value = await operation(cancellation);
      if (!_result.isCompleted) {
        _result.complete(cancellation.isCancelled ? null : value);
      }
    } catch (error, stackTrace) {
      if (!_result.isCompleted) {
        if (cancellation.isCancelled) {
          _result.complete(null);
        } else {
          _result.completeError(error, stackTrace);
        }
      }
    }
  }

  void cancelBeforeStart() {
    cancellation._cancel();
    if (!_result.isCompleted) _result.complete(null);
  }

  void cancelWhileActive() => cancellation._cancel();
}
