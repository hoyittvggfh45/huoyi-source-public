import 'models.dart';

class HongguoCloudProgress {
  const HongguoCloudProgress({
    required this.seriesId,
    required this.episodeId,
    required this.episodeIndex,
    required this.position,
    required this.duration,
    required this.updatedAt,
  });

  final String seriesId;
  final String episodeId;
  final int episodeIndex;
  final double position;
  final double duration;
  final DateTime updatedAt;

  factory HongguoCloudProgress.fromJson(Map<String, dynamic> json) {
    return HongguoCloudProgress(
      seriesId: json['seriesId'] as String? ?? '',
      episodeId: json['episodeId'] as String? ?? '',
      episodeIndex: intValue(json['episodeIndex']),
      position: (json['position'] as num?)?.toDouble() ?? 0,
      duration: (json['duration'] as num?)?.toDouble() ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'].toString()) ?? DateTime(2000),
    );
  }
}

class HongguoResumeTarget {
  const HongguoResumeTarget({required this.index, required this.position});

  final int index;
  final double position;
}

HongguoResumeTarget hongguoResumeTarget({
  required List<String> episodeIds,
  String? episodeId,
  double position = 0,
  bool completed = false,
}) {
  if (episodeIds.isEmpty) {
    return const HongguoResumeTarget(index: 0, position: 0);
  }
  final index = episodeId == null ? -1 : episodeIds.indexOf(episodeId);
  if (index < 0) return const HongguoResumeTarget(index: 0, position: 0);
  if (completed) {
    return HongguoResumeTarget(
      index: (index + 1).clamp(0, episodeIds.length - 1),
      position: 0,
    );
  }
  return HongguoResumeTarget(
    index: index,
    position: position < 0 ? 0 : position,
  );
}

HongguoResumeTarget? hongguoResumeProgress({
  required List<String> episodeIds,
  required String seriesId,
  int? localIndex,
  double localPosition = 0,
  DateTime? localUpdatedAt,
  HongguoCloudProgress? cloud,
  bool preferCloud = false,
}) {
  if (episodeIds.isEmpty) return null;
  HongguoResumeTarget? remote;
  if (cloud != null && cloud.seriesId == seriesId) {
    final byId = episodeIds.indexOf(cloud.episodeId);
    final index = byId >= 0
        ? byId
        : cloud.episodeIndex >= 0 && cloud.episodeIndex < episodeIds.length
        ? cloud.episodeIndex
        : -1;
    if (index >= 0) {
      remote = HongguoResumeTarget(
        index: index,
        position: cloud.position < 0 ? 0 : cloud.position,
      );
    }
  }
  HongguoResumeTarget? local;
  if (localIndex != null &&
      localIndex >= 0 &&
      localIndex < episodeIds.length) {
    local = HongguoResumeTarget(
      index: localIndex,
      position: localPosition < 0 ? 0 : localPosition,
    );
  }
  if (preferCloud && remote != null) return remote;
  if (remote != null &&
      (local == null ||
          localUpdatedAt == null ||
          cloud!.updatedAt.isAfter(localUpdatedAt))) {
    return remote;
  }
  return local;
}
