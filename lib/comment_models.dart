class VideoComment {
  const VideoComment({
    required this.id,
    required this.videoKey,
    required this.text,
    required this.timeMs,
    required this.senderId,
    required this.nickname,
    required this.createdAt,
  });

  final String id;
  final String videoKey;
  final String text;
  final int timeMs;
  final String senderId;
  final String nickname;
  final int createdAt;

  factory VideoComment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final videoKey = json['videoKey'];
    final text = json['text'];
    final timeMs = json['timeMs'];
    final senderId = json['senderId'];
    final nickname = json['nickname'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        id.isEmpty ||
        videoKey is! String ||
        videoKey.isEmpty ||
        text is! String ||
        text.trim().isEmpty ||
        text.runes.length > 200 ||
        timeMs is! int ||
        timeMs < 0 ||
        senderId is! String ||
        senderId.isEmpty ||
        nickname is! String ||
        nickname.runes.length > 40 ||
        createdAt is! int ||
        createdAt <= 0) {
      throw const FormatException('评论数据无效');
    }
    return VideoComment(
      id: id,
      videoKey: videoKey,
      text: text,
      timeMs: timeMs,
      senderId: senderId,
      nickname: nickname,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'videoKey': videoKey,
    'text': text,
    'timeMs': timeMs,
    'senderId': senderId,
    'nickname': nickname,
    'createdAt': createdAt,
  };
}

String commentRelativeTime(int createdAtMs, int nowMs) {
  final diff = nowMs - createdAtMs;
  if (diff < 60000) return '刚刚';
  if (diff < 3600000) return '${diff ~/ 60000}分钟前';
  if (diff < 86400000) return '${diff ~/ 3600000}小时前';
  return '${diff ~/ 86400000}天前';
}

String commentDisplayName(VideoComment comment) {
  if (comment.nickname.isNotEmpty) return comment.nickname;
  final sender = comment.senderId;
  final tail = sender.length >= 4 ? sender.substring(sender.length - 4) : sender;
  return '用户$tail';
}

String commentThreadKey(String dramaId, String episodeId) =>
    '$dramaId:$episodeId';
