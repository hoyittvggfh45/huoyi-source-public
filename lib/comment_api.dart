import 'dart:convert';
import 'dart:io';

import 'comment_models.dart';
import 'relay_cf/cf_relay_constants.dart';

class CommentApiException implements Exception {
  const CommentApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class CommentPageResult {
  const CommentPageResult({required this.items, required this.nextBefore});

  final List<VideoComment> items;
  final String? nextBefore;
}

abstract class CommentApi {
  Future<CommentPageResult> fetch({
    required String videoKey,
    int limit = 100,
    String? before,
  });

  Future<VideoComment> post({
    required String videoKey,
    required String text,
    required int timeMs,
    required String senderId,
    required String nickname,
  });
}

class CommentApiClient implements CommentApi {
  CommentApiClient({HttpClient? http, String? baseUrl})
    : _http = http ?? HttpClient(),
      _baseUrl = baseUrl ?? cfHttpBaseForWs(cfRelayWsUrl);

  static const Duration _timeout = Duration(seconds: 10);

  final HttpClient _http;
  final String _baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$_baseUrl$path').replace(queryParameters: query);

  @override
  Future<CommentPageResult> fetch({
    required String videoKey,
    int limit = 100,
    String? before,
  }) async {
    final query = <String, String>{'videoKey': videoKey, 'limit': '$limit'};
    if (before != null) query['before'] = before;
    final uri = _uri('/comments', query);
    final request = await _http.getUrl(uri).timeout(_timeout);
    final response = await request.close().timeout(_timeout);
    final body = await response.transform(utf8.decoder).join().timeout(_timeout);
    if (response.statusCode != 200) {
      throw CommentApiException('评论加载失败（${response.statusCode}）');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const CommentApiException('评论数据无效');
    }
    final rows = decoded['items'];
    if (rows is! List) {
      throw const CommentApiException('评论数据无效');
    }
    final items = <VideoComment>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        try {
          items.add(VideoComment.fromJson(row));
        } catch (_) {}
      }
    }
    final next = decoded['nextBefore'];
    return CommentPageResult(
      items: items,
      nextBefore: next is String && next.isNotEmpty ? next : null,
    );
  }

  @override
  Future<VideoComment> post({
    required String videoKey,
    required String text,
    required int timeMs,
    required String senderId,
    required String nickname,
  }) async {
    final uri = _uri('/comments');
    final request = await _http.postUrl(uri).timeout(_timeout);
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'videoKey': videoKey,
        'text': text,
        'timeMs': timeMs,
        'senderId': senderId,
        'nickname': nickname,
      }),
    );
    final response = await request.close().timeout(_timeout);
    final body = await response.transform(utf8.decoder).join().timeout(_timeout);
    if (response.statusCode == 429) {
      throw const CommentApiException('发得太快了，稍后再试');
    }
    if (response.statusCode != 200 && response.statusCode != 201) {
      throw CommentApiException('评论发送失败（${response.statusCode}）');
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const CommentApiException('评论数据无效');
    }
    return VideoComment.fromJson(decoded);
  }
}
