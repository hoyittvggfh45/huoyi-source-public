import 'hongguo_series.dart';
import 'models.dart';

class HongguoRelatedSeason {
  const HongguoRelatedSeason({
    required this.drama,
    required this.season,
    required this.unit,
    required this.upcoming,
  });

  final Drama drama;
  final int season;
  final String unit;
  final bool upcoming;

  String get label =>
      upcoming
          ? '第 $season $unit · 待上线 · 预约'
          : '第 $season $unit · 已上线';

  Map<String, dynamic> toJson() => {
    'seriesId': drama.id,
    'title': drama.title,
    'cover': drama.cover,
    'season': season,
    'unit': unit,
    'upcoming': upcoming,
  };
}

class HongguoRelated {
  static List<HongguoRelatedSeason> fetchRelatedSeasons({
    required Drama current,
    required List<Drama> candidates,
    List<HongguoRelatedSeason> remoteRows = const [],
  }) {
    final byId = <String, HongguoRelatedSeason>{};
    for (final row in remoteRows) {
      if (row.drama.id.isEmpty || row.drama.id == current.id) continue;
      byId[row.drama.id] = row;
    }
    final entries = hongguoSeriesEntries(current, candidates);
    for (final entry in entries) {
      if (entry.drama.id == current.id) continue;
      byId.putIfAbsent(
        entry.drama.id,
        () => HongguoRelatedSeason(
          drama: entry.drama,
          season: entry.season,
          unit: entry.unit,
          upcoming: false,
        ),
      );
    }
    final rows = byId.values.toList()
      ..sort((a, b) {
        final season = a.season.compareTo(b.season);
        if (season != 0) return season;
        return a.drama.title.compareTo(b.drama.title);
      });
    return rows;
  }

  static HongguoRelatedSeason? nextSeason({
    required Drama current,
    required List<HongguoRelatedSeason> rows,
  }) {
    final info = hongguoSeriesInfo(current);
    final currentSeason = info?.season ?? 1;
    final currentKey = info?.key;
    final matches =
        rows.where((row) {
          if (row.upcoming || row.drama.id == current.id) return false;
          if (row.season != currentSeason + 1) return false;
          if (currentKey == null) return true;
          final rowInfo = hongguoSeriesInfo(row.drama);
          return rowInfo?.key == currentKey;
        }).toList();
    return matches.length == 1 ? matches.first : null;
  }
}
