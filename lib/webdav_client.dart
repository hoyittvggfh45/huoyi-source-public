import 'dart:convert';
import 'dart:io';

typedef WebdavTransport =
    Future<WebdavResponse> Function(
      String method,
      Uri url, {
      Map<String, String>? headers,
      List<int>? body,
    });

class WebdavResponse {
  const WebdavResponse(this.statusCode, this.body);

  final int statusCode;
  final List<int> body;

  String get text => utf8.decode(body, allowMalformed: true);
}

class WebdavException implements Exception {
  const WebdavException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => 'WebdavException: $message';
}

String? webdavValidateAddress(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'WebDAV 地址为空';
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      !(uri.scheme == 'http' || uri.scheme == 'https') ||
      uri.host.isEmpty) {
    return 'WebDAV 地址须为 http/https 且含主机名';
  }
  return null;
}

String webdavJoinUrl(String base, String fileName) {
  final error = webdavValidateAddress(base);
  if (error != null) throw FormatException(error);
  final uri = Uri.parse(base.trim());
  final path = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
  return uri.replace(path: '$path$fileName').toString();
}

String webdavBasicAuthHeader(String username, String password) =>
    'Basic ${base64Encode(utf8.encode('$username:$password'))}';

class WebdavClient {
  WebdavClient({
    required this.baseUrl,
    this.username = '',
    this.password = '',
    WebdavTransport? transport,
  }) : _transport = transport ?? _defaultTransport;

  final String baseUrl;
  final String username;
  final String password;
  final WebdavTransport _transport;

  Map<String, String> get authHeaders => username.isEmpty
      ? const {}
      : {'Authorization': webdavBasicAuthHeader(username, password)};

  Future<void> upload(String fileName, String content) async {
    final url = webdavJoinUrl(baseUrl, fileName);
    final response = await _transport(
      'PUT',
      Uri.parse(url),
      headers: {
        ...authHeaders,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: utf8.encode(content),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw WebdavException(
        '上传失败（${response.statusCode}）',
        response.statusCode,
      );
    }
  }

  Future<String> download(String fileName) async {
    final url = webdavJoinUrl(baseUrl, fileName);
    final response = await _transport(
      'GET',
      Uri.parse(url),
      headers: authHeaders,
    );
    if (response.statusCode != 200) {
      throw WebdavException(
        '下载失败（${response.statusCode}）',
        response.statusCode,
      );
    }
    return response.text;
  }

  static Future<WebdavResponse> _defaultTransport(
    String method,
    Uri url, {
    Map<String, String>? headers,
    List<int>? body,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.openUrl(method, url);
      headers?.forEach(request.headers.set);
      if (body != null) request.add(body);
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (list, chunk) => list..addAll(chunk),
      );
      return WebdavResponse(response.statusCode, bytes);
    } finally {
      client.close();
    }
  }
}
