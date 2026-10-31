import 'dart:async';

class DramaPagePrefetcher {
  bool _running = false;

  bool get running => _running;

  Future<void> run({
    required bool Function() isCurrent,
    required bool Function() isBusy,
    required Future<bool> Function() loadMore,
    int maxLoads = 5,
  }) async {
    if (_running) return;
    _running = true;
    try {
      var loads = 0;
      while (isCurrent() && loads < maxLoads) {
        while (isBusy()) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (!isCurrent()) return;
        }
        if (!isCurrent()) return;
        final progressed = await loadMore();
        loads++;
        if (!isCurrent()) return;
        if (!progressed) return;
      }
    } finally {
      _running = false;
    }
  }
}
