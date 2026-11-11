class HongguoSleepTimer {
  HongguoSleepTimer({int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _now;
  int? _deadline;
  int _episodesLeft = 0;

  bool get active => _deadline != null || _episodesLeft > 0;

  int get episodesLeft => _episodesLeft;

  void cancel() {
    _deadline = null;
    _episodesLeft = 0;
  }

  void afterMinutes(int minutes) {
    if (minutes < 1 || minutes > 180) {
      throw ArgumentError('定时分钟须在 1 到 180 之间');
    }
    cancel();
    _deadline = _now() + minutes * 60000;
  }

  void afterEpisodes(int count) {
    if (count < 1 || count > 10) {
      throw ArgumentError('定时集数须在 1 到 10 之间');
    }
    cancel();
    _episodesLeft = count;
  }

  int? remainingMillis() {
    final deadline = _deadline;
    if (deadline == null) return null;
    final remaining = deadline - _now();
    return remaining < 0 ? 0 : remaining;
  }

  bool poll() {
    final deadline = _deadline;
    if (deadline == null || _now() < deadline) return false;
    cancel();
    return true;
  }

  bool episodeEnded() {
    if (poll()) return true;
    if (_episodesLeft <= 0) return false;
    _episodesLeft--;
    return _episodesLeft == 0;
  }

  String label() {
    final remaining = remainingMillis();
    if (remaining != null) return '${(remaining + 59999) ~/ 60000} 分钟后';
    if (_episodesLeft > 0) return '再播完 $_episodesLeft 集';
    return '关闭';
  }
}
