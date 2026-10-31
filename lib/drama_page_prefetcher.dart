import 'dart:async';

class DramaPagePrefetcher {
  bool _running = false;

  bool get running => _running;

  Future<void> run({
    required bool Function() isCurrent,
    required bool Function() isBusy,
    required Future<bool> Function() loadMore,
  }) async {
    if (_running) return;
    _running = true;
    try {
      while (isCurrent()) {
        while (isBusy()) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!isCurrent()) return;
        }
        if (!isCurrent()) return;
        final progressed = await loadMore();
        if (!isCurrent()) return;
        if (!progressed) return;
      }
    } finally {
      _running = false;
    }
  }
}
